import AppKit
import SwiftUI

/// Standard macOS file drag: publishes a file URL, never renames or moves the source.
func audioDragWriter(for url: URL) -> NSPasteboardWriting? {
    guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
    return url as NSURL
}

struct NativeFileDrag: NSViewRepresentable {
    let path: String
    var additionalPaths: [String] = []
    var compact = false
    var enabled = true
    var onFinish: (Bool) -> Void = { _ in }
    func makeNSView(context: Context) -> FileDragHandle { FileDragHandle() }
    func updateNSView(_ view: FileDragHandle, context: Context) {
        view.fileURL = URL(fileURLWithPath: path)
        view.additionalURLs = additionalPaths.map { URL(fileURLWithPath:$0) }
        view.compact = compact
        view.available = enabled
        view.onFinish = onFinish
        view.toolTip = enabled ? "按住拖动原素材到 Final Cut Pro 的事件或时间线" : "素材离线，连接原始磁盘后可拖入"
        view.setAccessibilityLabel(compact ? "拖出素材文件" : "拖入 FCP")
        view.setAccessibilityHelp(view.toolTip)
        view.needsDisplay = true
    }
}

final class FileDragHandle: NSView, NSDraggingSource {
    var fileURL = URL(fileURLWithPath: "/")
    var additionalURLs: [URL] = []
    var compact = false
    var available = true
    var onFinish: (Bool) -> Void = { _ in }
    private var down: NSPoint?
    private var didStart = false
    private var dragPaths:[String]=[]
    private var dragProject=""
    private var dragCompletion:((Bool)->Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if available { addCursorRect(bounds, cursor: .openHand) } }
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(calibratedRed: 0.74, green: 0.90, blue: 0.46, alpha: available ? 1 : 0.28)
        (compact ? color.withAlphaComponent(available ? 0.10 : 0.04) : color).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        let ink = compact ? color : NSColor(calibratedWhite: 0.09, alpha: 1)
        let text = compact ? "↗" : "↗  按住拖入 FCP"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: compact ? 17 : 12, weight: .semibold), .foregroundColor: ink]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) {
        down = event.locationInWindow; didStart = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard available, !didStart, let down = down,
              hypot(event.locationInWindow.x-down.x, event.locationInWindow.y-down.y) > 3,
              let writer = audioDragWriter(for: fileURL) else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let image = NSWorkspace.shared.icon(forFile: fileURL.path)
        image.size = NSSize(width: 48, height: 48)
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x-24, y: p.y-24, width: 48, height: 48), contents: image)
        var draggingItems = [item]
        for url in additionalURLs {
            guard let writer=audioDragWriter(for:url) else { return }
            let entry=NSDraggingItem(pasteboardWriter:writer)
            entry.setDraggingFrame(NSRect(x:p.x-24,y:p.y-24,width:48,height:48),contents:NSWorkspace.shared.icon(forFile:url.path))
            draggingItems.append(entry)
        }
        didStart=true
        dragPaths=([fileURL]+additionalURLs).map(\.path)
        dragProject=ShelfWorkspace.shared.current
        dragCompletion=onFinish
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
    override func mouseUp(with event: NSEvent) { down = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        down = nil; didStart = false
        let accepted=operation.contains(.copy)
        let completion=dragCompletion
        let paths=dragPaths, project=dragProject
        dragCompletion=nil; dragPaths=[]; dragProject=""
        completion?(accepted)
        if ShelfWorkspace.shared.recordDrag(paths:paths,project:project,accepted:accepted) {
            NotificationCenter.default.post(name:Notification.Name("SoundShelfDragAdded"),object:project)
        }
    }
}
