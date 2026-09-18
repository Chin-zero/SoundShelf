import Foundation
import CryptoKit
import Darwin
import CoreServices

func fileIdentity(_ path: String) -> String? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return "\(info.st_dev):\(info.st_ino)"
}
func digestFile(_ url: URL, cancelled: () -> Bool = { false }) throws -> String {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var before = stat()
    guard fstat(handle.fileDescriptor, &before) == 0 else { throw CocoaError(.fileReadUnknown) }
    var hash = SHA256()
    while true {
        if cancelled() { throw CocoaError(.userCancelled) }
        let data = try handle.read(upToCount: 2 * 1024 * 1024) ?? Data()
        if data.isEmpty { break }; hash.update(data: data)
    }
    var after = stat()
    guard fstat(handle.fileDescriptor, &after) == 0, before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw CocoaError(.fileReadUnknown) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func pathIsInside(_ path: String, _ directory: String) -> Bool { path == directory || (directory == "/" ? path.hasPrefix("/") : path.hasPrefix(directory + "/")) }
func minimalRoots(_ paths: [String]) -> [String] {
    var result: [String] = []
    for path in Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }).sorted(by: { $0.count < $1.count }) {
        if !result.contains(where: { pathIsInside(path, $0) }) { result.append(path) }
    }
    return result
}

final class AnnotationDiskStore {
    let url: URL
    let backups: URL
    private(set) var protected = false
    private var lastBackup = Date.distantPast
    init(folder: URL) { url = folder.appendingPathComponent("annotations.json"); backups = folder.appendingPathComponent("Backups") }
    func load() throws -> [String: Annotation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do { return try JSONDecoder().decode([String: Annotation].self, from: Data(contentsOf: url)) }
        catch { protected = true; throw error }
    }
    func backupExisting(force: Bool = false) throws {
        guard FileManager.default.fileExists(atPath: url.path), force || Date().timeIntervalSince(lastBackup) > 900 else { return }
        let bytes = try Data(contentsOf: url)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "annotations-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
        try bytes.write(to: backups.appendingPathComponent(name), options: .atomic)
        lastBackup = Date()
    }
    func save(_ annotations: [String: Annotation]) throws {
        guard !protected else { throw CocoaError(.fileWriteNoPermission) }
        // Verify the on-disk copy before replacing it, including modifications from outside this process.
        if FileManager.default.fileExists(atPath: url.path) {
            do { _ = try JSONDecoder().decode([String: Annotation].self, from: Data(contentsOf: url)) }
            catch { protected = true; throw error }
        }
        try backupExisting()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(annotations).write(to: url, options: .atomic)
    }
    func restore(_ annotations: [String: Annotation]) throws {
        // Preserve even a malformed original before an explicit restore.
        try backupExisting(force: true)
        let data = try JSONEncoder().encode(annotations)
        try data.write(to: url, options: .atomic)
        protected = false
    }
}

final class WorkTicket {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    let roots: [String]
    let onChange: ([String]) -> Void
    init(roots: [String], onChange: @escaping ([String]) -> Void) {
        self.roots = roots; self.onChange = onChange
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            let lost = (0..<count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 }
            watcher.onChange(lost ? watcher.roots : paths)
        }, &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.7,
        UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream = stream { FSEventStreamSetDispatchQueue(stream, DispatchQueue.main); FSEventStreamStart(stream) }
    }
    deinit { if let stream = stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}

func invalidAudioReason(_ url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let bytes = try? handle.read(upToCount: 1024) else { return nil }
    if bytes.isEmpty { return "空文件（0 字节），没有音频数据，需要重新获取原素材。" }
    let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.hasPrefix("<!doctype html") || text.hasPrefix("<html") { return "文件内容是网页，并非音频。下载时保存了网页，需要重新获取原音频。" }
    return nil
}
