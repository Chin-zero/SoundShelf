import AppKit
import AVKit

/// A separate preview player keeps the card silent while the large window is open.
final class LargeVideoPreview: NSObject, NSWindowDelegate {
    static let shared = LargeVideoPreview()
    private var previewWindow: NSWindow?
    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    var isOpen: Bool { previewWindow?.isVisible == true }

    func open(_ item: AudioItem, audio: AudioPlayback, replace: Bool = false) {
        guard item.isVideo, item.online, FileManager.default.isReadableFile(atPath:item.path) else {
            audio.error = "素材离线或无法读取，请连接素材硬盘。"; return
        }
        if isOpen && !replace { close(); return }
        let existingWindow=previewWindow
        player?.pause(); statusObserver=nil
        let position = audio.position
        audio.pauseForLargePreview()
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? NSSize(width:1200,height:800)
        let ratio = CGFloat(item.videoWidth ?? 1920) / CGFloat(max(1,item.videoHeight ?? 1080))
        let height = min(720, available.height-110)
        let width = min(1100, available.width-100, max(360,height*ratio))
        let window = existingWindow ?? NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:min(height,width/ratio)),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = item.name + " · ← → 切换 · 空格 / Esc 关闭预览"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width:320,height:220)
        let view = AVPlayerView(); view.controlsStyle = .floating; view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        let asset = AVPlayerItem(url:URL(fileURLWithPath:item.path))
        let video = AVPlayer(playerItem:asset); video.volume = Float(audio.volume)
        player = video; view.player = video; window.contentView = view; previewWindow = window
        statusObserver = asset.observe(\.status,options:[.initial,.new]) { [weak self, weak audio] current,_ in
            DispatchQueue.main.async {
                guard let self = self, self.player === video else { return }
                if current.status == .readyToPlay {
                    let duration = current.duration.seconds
                    let start = position.isFinite && position < duration ? max(0,position) : 0
                    video.seek(to:CMTime(seconds:start,preferredTimescale:600)) { [weak self] _ in
                        DispatchQueue.main.async { if self?.player === video { video.play() } }
                    }
                } else if current.status == .failed {
                    self.close(); audio?.error = "视频无法预览：" + (current.error?.localizedDescription ?? "编码不受支持")
                }
            }
        }
        if existingWindow == nil { window.center() }; window.makeKeyAndOrderFront(nil)
    }
    func close() { previewWindow?.close() }
    func windowWillClose(_ notification: Notification) {
        player?.pause(); player?.replaceCurrentItem(with:nil); player = nil
        statusObserver = nil; previewWindow = nil
    }
}
