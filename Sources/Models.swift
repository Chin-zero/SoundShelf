import Foundation
import CoreFoundation
import AVFoundation
import AppKit
import Combine

struct Rule: Codable { var kind: String; var dimension: String; var label: String; var keywords: [String] }
struct Cue: Codable, Identifiable { var id = UUID().uuidString; var time: Double; var title: String }
struct Annotation: Codable {
    var favorite = false
    var note = ""
    var tags: [String] = []
    var hiddenTags: [String] = []
    var cues: [Cue] = []
    var collection = ""
    var confirmed = false
    var lastUsed: Double = 0
}
struct AudioItem: Codable, Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var source: String
    var relative: String
    var kind: String
    var tags: [String]
    var size: Int64
    var modified: Double
    var duration: Double?
    var sampleRate: Double?
    var channels: Int?
    var online: Bool
    var contentDigest: String?
    var fileIdentity: String?
    var metadataError: String?
    var classificationVersion: Int?
    var videoWidth: Int?
    var videoHeight: Int?
    var frameRate: Double?
    var isVideo: Bool { videoExtensions.contains(URL(fileURLWithPath:path).pathExtension.lowercased()) }
    var folderCategory: String {
        let folders = relative.split(separator: "/").dropLast()
        return folders.count > 1 ? folders.dropFirst().joined(separator: " / ") : ""
    }
    var folderKey: String { source + " ▸ " + folderCategory }
    var ext: String { URL(fileURLWithPath: path).pathExtension.uppercased() }
}
struct Settings: Codable { var roots: [String]; var projectFolder: String = "" }
func clockText(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "—" }
    if t < 60 { return String(format: "00:%04.1f", t) }
    return String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
}

func readSourceDescription(folder: URL) -> String {
    let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    for name in ["说明.txt", "README.txt", "readme.txt"] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
        for encoding in [String.Encoding.utf8, gb18030, .utf16] {
            if let text = String(data: data, encoding: encoding) { return String(text.prefix(16000)) }
        }
    }
    return ""
}

func copyAudioFile(source: URL, folder: URL) throws -> URL {
    var target = folder.appendingPathComponent(source.lastPathComponent)
    var n = 2
    while FileManager.default.fileExists(atPath: target.path) {
        target = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + " (\(n))." + source.pathExtension)
        n += 1
    }
    try FileManager.default.copyItem(at: source, to: target)
    return target
}

final class Classifier {
    static let version = 3
    let rules: [Rule]
    init(url: URL) { rules = (try? JSONDecoder().decode([Rule].self, from: Data(contentsOf: url))) ?? [] }
    func classify(_ path: String) -> (String, [String]) {
        if videoExtensions.contains(URL(fileURLWithPath:path).pathExtension.lowercased()) { return ("视频", videoTags(path)) }
        let lower = path.lowercased()
        let kind = ["bgm", "音乐合集", "背景音乐", "配乐", "music"].contains(where: lower.contains) ? "音乐" : "音效"
        let directories = path.split(separator: "/").dropLast()
        // Music labels describe the curated folder, not an unrelated song title.
        // Omit the generic collection root (e.g. Vlog BGM音乐合集) when a detailed folder exists.
        let musicScope = (directories.count > 1 ? directories.dropFirst().joined(separator: "/") : directories.joined(separator: "/")).lowercased()
        let scope = kind == "音乐" ? musicScope : lower
        let compactScope = scope.filter { !$0.isWhitespace }
        let normalized = " " + scope.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        let tags = rules.filter { rule in
            (rule.kind.isEmpty || rule.kind == kind) && rule.keywords.contains { key in
                if key.unicodeScalars.contains(where: { $0.value > 127 }) { return scope.contains(key) || compactScope.contains(key) }
                return normalized.contains(" " + key + " ")
            }
        }.map { $0.dimension + ":" + $0.label }
        return (kind, Array(Set(tags)).sorted())
    }
}

final class Library: ObservableObject {
    @Published var items: [AudioItem] = [] { didSet { lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.path,$0) }) } }
    private(set) var lookup: [String: AudioItem] = [:]
    @Published var annotations: [String: Annotation] = [:]
    @Published var settings: Settings
    @Published var scanning = false
    @Published var status = "正在打开本机素材库…"
    @Published var maintenanceStatus = ""
    @Published var error: String?
    @Published var storageProtected = false
    @Published var revision = 0
    let home: URL
    let dataFolder: URL
    let classifier: Classifier
    let store: AnnotationDiskStore
    private let worker = DispatchQueue(label: "soundshelf.index", qos: .utility)
    private let writer = DispatchQueue(label: "soundshelf.persistence", qos: .utility)
    private let hashWorker = DispatchQueue(label: "soundshelf.hashes", qos: .utility)
    private var hashTicket: WorkTicket?
    private var watcher: FolderWatcher?
    private var monitor: Timer?
    private var saveTask: DispatchWorkItem?
    private var scanTask: DispatchWorkItem?
    private var queuedScopes: [String] = []
    private var rootAvailability: [String: Bool] = [:]
    var indexURL: URL { dataFolder.appendingPathComponent("index.json") }
    var settingsURL: URL { dataFolder.appendingPathComponent("settings.json") }
    var annotationURL: URL { store.url }
    init(home: URL, storage: URL? = nil) {
        self.home = home
        self.dataFolder = storage ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SoundShelf")
        self.classifier = Classifier(url: Bundle.main.resourceURL!.appendingPathComponent("taxonomy.json"))
        self.settings = Settings(roots: [])
        self.store = AnnotationDiskStore(folder: dataFolder)
        do {
            try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
            let legacy = home.appendingPathComponent("Data")
            let marker = dataFolder.appendingPathComponent("migration-complete")
            if !FileManager.default.fileExists(atPath: marker.path), FileManager.default.fileExists(atPath: legacy.appendingPathComponent("index.json").path) {
                for name in ["index.json", "annotations.json", "settings.json", "hash-migration.json"] {
                    let from = legacy.appendingPathComponent(name), to = dataFolder.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) { try FileManager.default.copyItem(at: from, to: to) }
                }
                try Date().description.write(to: marker, atomically: true, encoding: .utf8)
            }
            annotations = try store.load()
            try store.backupExisting(force: true)
        } catch {
            storageProtected = true
            self.error = "本机收藏进入保护模式，原文件不会被覆盖。请在“目录与备份”中恢复有效备份。\n" + error.localizedDescription
        }
        if let data = try? Data(contentsOf: settingsURL), let s = try? JSONDecoder().decode(Settings.self, from: data) { settings = s }
        settings.roots = minimalRoots(settings.roots)
        let roots = settings.roots
        worker.async {
            var existing = (try? Data(contentsOf: self.indexURL)).flatMap { try? JSONDecoder().decode([AudioItem].self, from: $0) } ?? []
            struct HashMigration: Codable { var digest: String; var size: Int64; var modified: Double }
            let manifest = (try? Data(contentsOf: self.dataFolder.appendingPathComponent("hash-migration.json"))).flatMap { try? JSONDecoder().decode([String: HashMigration].self, from: $0) } ?? [:]
            let availability = Dictionary(uniqueKeysWithValues: roots.map { ($0, FileManager.default.fileExists(atPath: $0)) })
            for i in existing.indices {
                if existing[i].classificationVersion != Classifier.version {
                    let (kind, tags) = self.classifier.classify(existing[i].relative)
                    existing[i].kind = kind; existing[i].tags = tags;
                    if existing[i].isVideo, let w = existing[i].videoWidth, let h = existing[i].videoHeight { existing[i].tags.append(h > w ? "画幅:竖屏" : h == w ? "画幅:方形" : "画幅:横屏") }; existing[i].classificationVersion = Classifier.version
                }
                if !roots.contains(where: { availability[$0] == true && pathIsInside(existing[i].path, $0) }) { existing[i].online = false }
                if let h = manifest[existing[i].path], h.size == existing[i].size, abs(h.modified - existing[i].modified) < 0.01 { existing[i].contentDigest = h.digest }
            }
            let ready = existing
            DispatchQueue.main.async {
                self.items = ready; self.revision += 1
                self.installWatcher(); self.scan()
                self.monitor = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkVolumes() }
            }
        }
    }
    func annotation(_ id: String) -> Annotation { annotations[id] ?? Annotation() }
    func effectiveTags(_ item: AudioItem) -> [String] {
        let a = annotation(item.id); return Array(Set(item.tags.filter { !a.hiddenTags.contains($0) } + a.tags)).sorted()
    }
    func update(_ id: String, _ body: (inout Annotation) -> Void) {
        updateMany([id],body)
    }
    func updateMany(_ ids:[String], _ body:(inout Annotation)->Void) {
        guard !storageProtected else { error = "收藏处于保护模式，请先从备份恢复。"; return }
        var changed=annotations
        for id in Set(ids) { var a=changed[id] ?? Annotation(); body(&a); changed[id]=a }
        annotations=changed; revision += 1
        saveTask?.cancel(); let work = DispatchWorkItem { [weak self] in self?.saveAnnotations() }; saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func markUsed(_ item: AudioItem) {
        update(item.id) { $0.lastUsed = Date().timeIntervalSince1970 }
        status = "已交给目标应用：" + item.name
    }
    func saveAnnotations() {
        guard !storageProtected else { return }
        do { try store.save(annotations) }
        catch { storageProtected = store.protected; self.error = "收藏保存失败，原数据已保留：" + error.localizedDescription }
    }
    func write<T: Encodable>(_ value: T, to url: URL) {
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic) }
        catch { self.error = "保存失败：" + error.localizedDescription }
    }
    func saveSettings() { write(settings, to: settingsURL) }
    func installWatcher() {
        rootAvailability = Dictionary(uniqueKeysWithValues: settings.roots.map { ($0, FileManager.default.fileExists(atPath: $0)) })
        watcher = FolderWatcher(roots: settings.roots.filter { rootAvailability[$0] == true }) { [weak self] paths in self?.scheduleChanged(paths) }
    }
    func checkVolumes() {
        let now = Dictionary(uniqueKeysWithValues: settings.roots.map { ($0, FileManager.default.fileExists(atPath: $0)) })
        if now != rootAvailability { installWatcher(); scan() }
    }
    func scheduleChanged(_ paths: [String]) {
        let allowed = paths.filter { path in !pathIsInside(path, home.path) && !pathIsInside(path, dataFolder.path) && settings.roots.contains { pathIsInside(path, $0) } }
        guard !allowed.isEmpty else { return }
        let directories = allowed.map { path -> String in
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { return path }
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        queuedScopes = minimalRoots(queuedScopes + directories)
        scanTask?.cancel(); let task = DispatchWorkItem { [weak self] in self?.flushChanges() }; scanTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }
    func flushChanges() {
        guard !scanning, !queuedScopes.isEmpty else { return }
        let scopes = queuedScopes; queuedScopes = []; scan(scopes: scopes)
    }
    func scan(automatic: Bool = false, scopes: [String]? = nil, retryErrors: Bool = false) {
        if scanning { queuedScopes = minimalRoots(queuedScopes + (scopes ?? settings.roots)); return }
        scanning = true; hashTicket?.cancel()
        status = scopes == nil ? "正在核对素材目录…" : "正在更新发生变化的目录…"
        let roots = settings.roots, scanScopes = minimalRoots(scopes ?? roots)
        let previous = items, excluded = home.path
        worker.async {
            let fm = FileManager.default
            let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.path, $0) })
            let identityGroups = Dictionary(grouping: previous.filter { $0.fileIdentity != nil }, by: { $0.fileIdentity! })
            var found: [String: AudioItem] = [:], moves: [(String, String)] = [], failedScopes = Set<String>()
            let extensions: Set<String> = Set(["wav","mp3","aiff","aif","m4a","aac","flac","caf","ogg"]).union(videoExtensions)
            for scope in scanScopes {
                guard let root = roots.first(where: { pathIsInside(scope, $0) }), fm.fileExists(atPath: scope) else { continue }
                var enumerationFailed = false
                guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: scope), includingPropertiesForKeys: [.isRegularFileKey,.fileSizeKey,.contentModificationDateKey], options: [.skipsHiddenFiles,.skipsPackageDescendants], errorHandler: { _, _ in enumerationFailed = true; return true }) else { failedScopes.insert(scope); continue }
                for case let url as URL in enumerator {
                    let path = url.standardizedFileURL.path
                    if pathIsInside(path, excluded) { enumerator.skipDescendants(); continue }
                    guard extensions.contains(url.pathExtension.lowercased()), let v = try? url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]), v.isRegularFile == true else { continue }
                    let modified = v.contentModificationDate?.timeIntervalSince1970 ?? 0, size = Int64(v.fileSize ?? 0)
                    let identity = fileIdentity(path)
                    if var item = old[path], item.modified == modified, item.size == size, (item.fileIdentity == nil || item.fileIdentity == identity) {
                        item.online = true; item.fileIdentity = identity; found[path] = item; continue
                    }
                    let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let (kind,tags) = self.classifier.classify(relative)
                    let source = relative.split(separator: "/").dropLast().first.map(String.init) ?? URL(fileURLWithPath: root).lastPathComponent
                    var item = AudioItem(path: path, name: url.deletingPathExtension().lastPathComponent, source: source, relative: relative, kind: kind, tags: tags, size: size, modified: modified, online: true, classificationVersion: Classifier.version)
                    item.fileIdentity = identity
                    if let identity = identity, let matches = identityGroups[identity], matches.count == 1, let before = matches.first, before.path != path, !fm.fileExists(atPath: before.path), before.size == size, before.modified == modified {
                        item.videoWidth = before.videoWidth; item.videoHeight = before.videoHeight; item.frameRate = before.frameRate
                        item.duration = before.duration; item.sampleRate = before.sampleRate; item.channels = before.channels
                        item.contentDigest = before.contentDigest; item.metadataError = before.metadataError
                        moves.append((before.path, path))
                    }
                    found[path] = item
                }
                if enumerationFailed { failedScopes.insert(scope) }
            }
            let movedPaths = Set(moves.map(\.0))
            for var item in previous where found[item.path] == nil && !movedPaths.contains(item.path) {
                if scanScopes.contains(where: { pathIsInside(item.path,$0) }) && !failedScopes.contains(where: { pathIsInside(item.path,$0) }) { item.online = fm.fileExists(atPath: item.path) }
                found[item.path] = item
            }
            let pending = found.values.filter { $0.online && $0.duration == nil && (retryErrors || $0.metadataError == nil) }
            let initial = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let resolvedMoves = moves
            DispatchQueue.main.async {
                self.items = initial; self.revision += 1
                for (from,to) in resolvedMoves {
                    if let a = self.annotations[from], self.annotations[to] == nil, !self.storageProtected { self.annotations[to] = a; self.annotations.removeValue(forKey: from) }
                }
                if !resolvedMoves.isEmpty { self.saveAnnotations() }
            }
            for item in pending {
                autoreleasepool {
                    do {
                        if item.isVideo {
                            let asset = AVURLAsset(url:URL(fileURLWithPath:item.path))
                            guard let track = asset.tracks(withMediaType:.video).first else { throw NSError(domain:"SoundShelf.Video",code:1,userInfo:[NSLocalizedDescriptionKey:"没有可读取的视频轨道"]) }
                            let seconds = asset.duration.seconds
                            guard seconds.isFinite, seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
                            let size = track.naturalSize.applying(track.preferredTransform)
                            found[item.path]?.duration = seconds; found[item.path]?.videoWidth = Int(abs(size.width)); found[item.path]?.videoHeight = Int(abs(size.height)); found[item.path]?.frameRate = Double(track.nominalFrameRate); found[item.path]?.metadataError = nil
                            found[item.path]?.tags.append(abs(size.height) > abs(size.width) ? "画幅:竖屏" : "画幅:横屏")
                            return
                        }
                        if let reason = invalidAudioReason(URL(fileURLWithPath: item.path)) { throw NSError(domain: "SoundShelf.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
                        let file = try AVAudioFile(forReading: URL(fileURLWithPath: item.path)); let rate = file.processingFormat.sampleRate
                        guard rate > 0, file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
                        found[item.path]?.duration = Double(file.length)/rate; found[item.path]?.sampleRate = rate
                        found[item.path]?.channels = Int(file.processingFormat.channelCount); found[item.path]?.metadataError = nil
                    } catch { found[item.path]?.metadataError = String(error.localizedDescription.prefix(200)) }
                }
            }
            let result = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.items = result; self.revision += 1; self.scanning = false
                let offline = result.filter { !$0.online }.count
                self.status = "\(result.count.formatted()) 个文件 · " + (offline > 0 ? "\(offline.formatted()) 个离线" : "目录变化自动更新")
                if !failedScopes.isEmpty { self.status += " · 部分目录读取受限，已保留原索引" }
                self.persistIndex()
                if !self.queuedScopes.isEmpty { self.flushChanges() } else { self.verifyDuplicates() }
            }
        }
    }
    func persistIndex() {
        let snapshot = items, url = indexURL
        writer.async {
            do { try JSONEncoder().encode(snapshot).write(to: url, options: .atomic) }
            catch { DispatchQueue.main.async { self.error = "本机索引保存失败：" + error.localizedDescription } }
        }
    }
    func verifyDuplicates() {
        let groups = Dictionary(grouping: items.filter(\.online), by: \.size)
        let pending = groups.values.filter { $0.count > 1 }.flatMap { $0 }.filter { $0.contentDigest == nil }
        guard !pending.isEmpty else { maintenanceStatus = "重复素材已按内容校验"; return }
        hashTicket?.cancel(); let ticket = WorkTicket(); hashTicket = ticket
        maintenanceStatus = "正在校验重复素材…"
        hashWorker.async {
            var hashes: [(String, Int64, Double, String)] = []
            for (i,item) in pending.enumerated() {
                if ticket.cancelled { return }
                if let hash = try? digestFile(URL(fileURLWithPath: item.path), cancelled: { ticket.cancelled }) { hashes.append((item.path,item.size,item.modified,hash)) }
                if (i+1) % 200 == 0 {
                    let batch = hashes; hashes = []
                    DispatchQueue.main.async { guard !ticket.cancelled else { return }; self.mergeHashes(batch); self.maintenanceStatus = "重复校验 \(i+1)/\(pending.count)" }
                }
            }
            let batch = hashes
            DispatchQueue.main.async { guard !ticket.cancelled else { return }; self.mergeHashes(batch); self.persistIndex(); self.maintenanceStatus = "重复素材已按内容校验" }
        }
    }
    func mergeHashes(_ values: [(String, Int64, Double, String)]) {
        let lookup = Dictionary(uniqueKeysWithValues: values.map { ($0.0,$0) }); var updated = items
        for i in updated.indices { if let h = lookup[updated[i].path], h.1 == updated[i].size, h.2 == updated[i].modified { updated[i].contentDigest = h.3 } }
        items = updated; revision += 1
    }
    func addRoot() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = true; p.prompt = "添加素材目录"
        if p.runModal() == .OK { settings.roots = minimalRoots(settings.roots + p.urls.map(\.path)); saveSettings(); installWatcher(); scan() }
    }
    func relocateRoot(_ oldRoot: String) {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.prompt = "选择此素材目录的新位置"
        guard p.runModal() == .OK, let folder = p.url else { return }
        let before = items.filter { pathIsInside($0.path,oldRoot) }, target = folder.path
        guard target != oldRoot else { return }
        scanning = true; status = "校验新目录与原素材的对应关系…"
        worker.async {
            var remapped: [(String, AudioItem)] = []
            for var item in before {
                let suffix = String(item.path.dropFirst(oldRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let url = folder.appendingPathComponent(suffix)
                guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path), (attr[.size] as? NSNumber)?.int64Value == item.size else { continue }
                let identity = fileIdentity(url.path)
                let sameIdentity = identity != nil && identity == item.fileIdentity
                let sameDigest = item.contentDigest != nil && (try? digestFile(url)) == item.contentDigest
                // The user selected a replacement root; same relative path, size and modification time are a conservative fallback for legacy entries.
                let sameLegacy = item.contentDigest == nil && abs(((attr[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) - item.modified) < 0.01
                guard sameIdentity || sameDigest || sameLegacy else { continue }
                let old = item.path; item.path = url.path; item.fileIdentity = identity; item.online = true; remapped.append((old,item))
            }
            let changes = remapped
            DispatchQueue.main.async {
                var map = Dictionary(uniqueKeysWithValues: self.items.map { ($0.path,$0) })
                for (old,item) in changes {
                    map.removeValue(forKey: old); map[item.path] = item
                    if let note = self.annotations[old], self.annotations[item.path] == nil, !self.storageProtected { self.annotations[item.path] = note; self.annotations.removeValue(forKey: old) }
                }
                self.items = map.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.settings.roots = minimalRoots(self.settings.roots.filter { $0 != oldRoot } + [target]); self.scanning = false
                self.saveAnnotations(); self.saveSettings(); self.persistIndex(); self.installWatcher(); self.revision += 1; self.scan()
            }
        }
    }
    @discardableResult func chooseProject() -> Bool {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.prompt = "选择另存位置"
        if p.runModal() == .OK, let url = p.url { settings.projectFolder = url.path; saveSettings(); return true }
        return false
    }
    func copyToProject(_ item: AudioItem) {
        guard chooseProject(), !settings.projectFolder.isEmpty else { return }
        do { let url = try copyAudioFile(source: URL(fileURLWithPath: item.path), folder: URL(fileURLWithPath: settings.projectFolder)); markUsed(item); NSWorkspace.shared.activateFileViewerSelecting([url]) }
        catch { self.error = "另存失败：" + error.localizedDescription }
    }
    func backup() {
        guard !storageProtected else { NSWorkspace.shared.open(store.backups); return }
        saveAnnotations(); let p = NSSavePanel(); p.nameFieldStringValue = "声屿收藏备份.json"
        if p.runModal() == .OK, let url = p.url { write(annotations,to:url) }
    }
    func restore() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false; p.directoryURL = store.backups
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let restored = try JSONDecoder().decode([String:Annotation].self, from: Data(contentsOf:url))
            var merged = annotations; merged.merge(restored) { _,incoming in incoming }
            try store.restore(merged); annotations = merged; storageProtected = false; revision += 1; status = "已恢复收藏与备注"
        } catch { self.error = "恢复失败，原数据仍被保留：" + error.localizedDescription }
    }
}

