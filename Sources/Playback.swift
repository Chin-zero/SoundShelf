import Foundation
import AVFoundation
import Combine
import CryptoKit

func validLoopRange(start: Double?, end: Double?, duration: Double) -> ClosedRange<Double>? {
    guard let a = start, let b = end, a.isFinite, b.isFinite, a >= 0, b <= duration, b-a >= 0.05 else { return nil }
    return a...b
}
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var selected: AudioItem?
    @Published var playing = false
    @Published var loading = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var peaks: [Float] = []
    @Published var loadingWave = false
    @Published var error: String?
    @Published var rangeStart: Double?
    @Published var rangeEnd: Double?
    @Published var loop = false { didSet { updateLoop() } }
    @Published var volume: Double = 0.75 { didSet { player?.volume = Float(volume); videoPlayer?.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "previewVolume") } }
    @Published var videoPlayer: AVPlayer?
    private var videoObservation: NSKeyValueObservation?
    private var videoEnd: NSObjectProtocol?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadTicket: WorkTicket?
    private var waveTicket: WorkTicket?
    private var playWhenReady = false
    private let loader = DispatchQueue(label: "soundshelf.audio", qos: .userInitiated)
    private let waves = DispatchQueue(label: "soundshelf.waveform", qos: .utility)
    let cacheFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/SoundShelf/Waveforms")
    var range: ClosedRange<Double>? { validLoopRange(start: rangeStart, end: rangeEnd, duration: duration) }
    override init() {
        super.init()
        if UserDefaults.standard.object(forKey: "previewVolume") != nil { volume = UserDefaults.standard.double(forKey: "previewVolume") }
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let video = self.videoPlayer {
                let t = video.currentTime().seconds
                if t.isFinite { self.position = t }
                if self.playing, self.loop, let r = self.range, t >= r.upperBound || t < r.lowerBound { self.seek(r.lowerBound) }
                return
            }
            guard let p = self.player, p.isPlaying else { return }
            if self.loop, let range = self.range, p.currentTime >= range.upperBound || p.currentTime < range.lowerBound { p.currentTime = range.lowerBound }
            let t = p.currentTime
            if abs(self.position-t) > 0.015 { self.position = t }
        }
    }
    func clearSelection() {
        loadTicket?.cancel(); waveTicket?.cancel(); playWhenReady = false
        player?.stop(); player = nil
        videoPlayer?.pause(); videoPlayer?.replaceCurrentItem(with:nil); videoPlayer = nil
        videoObservation = nil
        if let token = videoEnd { NotificationCenter.default.removeObserver(token); videoEnd = nil }
        selected = nil; playing = false; loading = false; loadingWave = false
        position = 0; duration = 0; peaks = []; rangeStart = nil; rangeEnd = nil; error = nil
    }
    func select(_ item: AudioItem, autoplay: Bool = true) {
        if selected?.id == item.id, (player != nil || videoPlayer != nil) { if autoplay { toggle() }; return }
        loadTicket?.cancel(); waveTicket?.cancel()
        videoPlayer?.pause(); videoPlayer = nil; videoObservation = nil
        if let token = videoEnd { NotificationCenter.default.removeObserver(token); videoEnd = nil }
        player?.stop(); player = nil; playing = false; position = 0; duration = item.duration ?? 0; peaks = []
        rangeStart = nil; rangeEnd = nil; selected = item; loading = true; loadingWave = false; playWhenReady = autoplay
        if item.isVideo { selectVideo(item, autoplay:autoplay); return }
        let task = WorkTicket(); loadTicket = task
        loader.async {
            guard !task.cancelled else { return }
            do {
                let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: item.path)); p.prepareToPlay()
                DispatchQueue.main.async {
                    guard !task.cancelled else { return }
                    p.delegate = self; p.volume = Float(self.volume); self.player = p; self.duration = p.duration; self.loading = false; self.updateLoop()
                    if self.playWhenReady { self.playing = p.play(); if !self.playing { self.error = "无法开始试听，请检查声音输出设备。" } }
                    self.waveform(item)
                }
            } catch { DispatchQueue.main.async { guard !task.cancelled else { return }; self.loading = false; self.error = "无法试听：" + error.localizedDescription } }
        }
    }
    func pauseForLargePreview() { playWhenReady = false; player?.pause(); videoPlayer?.pause(); playing = false }
    func toggle() {
        if let video = videoPlayer {
            if loading { playWhenReady.toggle(); return }
            if playing { video.pause(); playing = false }
            else { if position >= duration || (loop && range.map { !$0.contains(position) } == true) { seek(range?.lowerBound ?? 0) }; video.play(); playing = true }
            return
        }
        guard let p = player else { if loading { playWhenReady.toggle() }; return }
        if p.isPlaying { p.pause(); playing = false }
        else {
            if position >= duration { p.currentTime = loop ? range?.lowerBound ?? 0 : 0 }
            if loop, let range = range, !range.contains(p.currentTime) { p.currentTime = range.lowerBound }
            playing = p.play()
        }
    }
    func seek(_ time: Double) { let t = max(0,min(time,duration)); player?.currentTime = t; videoPlayer?.seek(to:CMTime(seconds:t,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero); position = t }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func playFrom(_ time: Double) {
        if let range = range, !range.contains(time) { loop = false }
        seek(time); if !playing { toggle() }
    }
    func setA() { rangeStart = min(position,max(0,duration-0.05)); if let b = rangeEnd, b <= rangeStart! { rangeEnd = nil }; updateLoop() }
    func setB() {
        let a = rangeStart ?? 0
        guard position-a >= 0.05 else { error = "B 点需要在 A 点之后。"; return }
        rangeStart = a; rangeEnd = min(position,duration); loop = true; updateLoop()
    }
    func clearRange() { rangeStart = nil; rangeEnd = nil; loop = false }
    func updateLoop() { player?.numberOfLoops = loop && range == nil ? -1 : 0 }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if loop, let range = range { player.currentTime = range.lowerBound; playing = player.play() }
        else { playing = false; position = duration }
    }
    func selectVideo(_ item: AudioItem, autoplay: Bool) {
        let avItem = AVPlayerItem(url:URL(fileURLWithPath:item.path))
        let video = AVPlayer(playerItem:avItem); video.volume = Float(volume); videoPlayer = video
        videoObservation = avItem.observe(\.status,options:[.initial,.new]) { [weak self] current,_ in
            DispatchQueue.main.async {
                guard let self = self, self.videoPlayer === video else { return }
                if current.status == .readyToPlay {
                    self.loading = false
                    let seconds = current.duration.seconds; if seconds.isFinite { self.duration = seconds }
                    if self.playWhenReady { video.play(); self.playing = true }
                } else if current.status == .failed { self.loading = false; self.playing = false; self.error = "视频无法预览：" + (current.error?.localizedDescription ?? "系统不支持此编码") }
            }
        }
        videoEnd = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:avItem,queue:.main) { [weak self] _ in
            guard let self = self else { return }
            if self.loop { self.seek(self.range?.lowerBound ?? 0); video.play() } else { self.playing = false; self.position = self.duration }
        }
    }
    func waveform(_ item: AudioItem) {
        waveTicket?.cancel(); let task = WorkTicket(); waveTicket = task; loadingWave = true
        let identity = item.contentDigest ?? "\(item.path)|\(item.size)|\(item.modified)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x",$0) }.joined()
        let cache = cacheFolder.appendingPathComponent(key + ".json")
        waves.async {
            guard !task.cancelled else { return }
            if let bytes = try? Data(contentsOf: cache), let saved = try? JSONDecoder().decode([Float].self, from: bytes), saved.count == 420, saved.allSatisfy(\.isFinite) {
                DispatchQueue.main.async { guard !task.cancelled else { return }; self.peaks = saved; self.loadingWave = false }; return
            }
            var peaks = [Float](repeating:0,count:420)
            if let file = try? AVAudioFile(forReading: URL(fileURLWithPath:item.path)), file.length > 0,
               let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:2048) {
                for i in peaks.indices {
                    if task.cancelled { return }
                    file.framePosition = min(file.length-1,AVAudioFramePosition(Double(i)/Double(peaks.count)*Double(file.length)))
                    if (try? file.read(into:buffer,frameCount:2048)) != nil, let channels = buffer.floatChannelData {
                        var p: Float = 0
                        for c in 0..<Int(buffer.format.channelCount) { for j in 0..<Int(buffer.frameLength) { p = max(p,abs(channels[c][j])) } }
                        peaks[i] = p
                    }
                }
                let peak = peaks.max() ?? 0
                if peak > 0 { peaks = peaks.map { pow($0/peak,0.65) } }
                if !task.cancelled, let bytes = try? JSONEncoder().encode(peaks) { try? bytes.write(to:cache,options:.atomic) }
            }
            let ready = peaks
            DispatchQueue.main.async { guard !task.cancelled else { return }; self.peaks = ready; self.loadingWave = false }
        }
    }
}
