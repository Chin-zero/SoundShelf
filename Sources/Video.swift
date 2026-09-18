import SwiftUI
import AVKit
import CryptoKit
let videoExtensions: Set<String> = ["mp4","mov","m4v","avi","mkv","webm"]
func videoTags(_ path:String) -> [String] {
    // Prefer the nearest descriptive category; never inherit every keyword in a pack title.
    let components = path.lowercased().split(separator:"/").map(String.init)
    let rules:[(String,[String])] = [
        ("动态背景",["animated backgrounds"]),("火焰转场",["flames transitions"]),
        ("胶片灼烧",["film burn","灼烧"]),("漏光",["light leak","leaking light","漏光"]),
        ("光线擦除",["light wipe"]),("散景",["bokeh"]),("闪光",["flash","闪烁"]),
        ("胶片颗粒",["grain","颗粒"]),("故障转场",["digi-transitions","glitch","数字故障"]),
        ("胶片纹理",["dynamixxx","胶片污渍"]),("字母动画",["letters"]),
        ("胶片边框",["film tape","border","边框"]),("太空光效",["space"]),
        ("教程演示",["instructions","效果展示","preview","demo","spectre"])]
    var category:String?
    for component in components.dropLast().reversed() {
        if let rule=rules.first(where:{ $0.1.contains(where:component.contains) }) { category=rule.0; break }
    }
    if category == nil, let name=components.last { category=rules.first(where:{ $0.1.contains(where:name.contains) })?.0 }
    var tags=["类别:" + (category ?? "其他视频")]
    if components.contains(where:{ $0.contains("transition") || $0.contains("转场") }) { tags.append("用途:转场") }
    if ["胶片纹理","胶片灼烧","胶片颗粒","胶片边框"].contains(category ?? "") { tags.append("风格:复古") }
    if category == "动态背景" { tags.append("用途:背景") }
    if category == "教程演示" { tags = ["类别:教程演示","用途:效果演示"] }
    return tags
}
struct VideoSurface: NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context) -> AVPlayerView { let view=AVPlayerView(); view.controlsStyle = .none; view.videoGravity = .resizeAspect; return view }
    func updateNSView(_ view:AVPlayerView,context:Context) { view.player=player }
}
final class ThumbnailService {
    static let shared=ThumbnailService()
    private let queue:OperationQueue = { let q=OperationQueue(); q.maxConcurrentOperationCount=2; q.qualityOfService = .utility; return q }()
    private let memory=NSCache<NSString,NSData>()
    init() { memory.totalCostLimit=32*1024*1024 }
    func load(_ item:AudioItem, completion:@escaping(Data?)->Void)->Operation {
        let key=SHA256.hash(data:Data("v2|\(item.path)|\(item.modified)|\(item.size)".utf8)).map { String(format:"%02x",$0) }.joined()
        let job=BlockOperation()
        job.addExecutionBlock { [weak job, weak self] in
            guard let job=job, let self=self, !job.isCancelled else { return }
            let cache=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/SoundShelf/Thumbnails")
            let url=cache.appendingPathComponent(key+".jpg")
            var bytes=self.memory.object(forKey:key as NSString).map { $0 as Data } ?? (try? Data(contentsOf:url))
            if bytes == nil && item.online {
                let generator=AVAssetImageGenerator(asset:AVURLAsset(url:URL(fileURLWithPath:item.path)))
                generator.appliesPreferredTrackTransform=true; generator.maximumSize=CGSize(width:560,height:320)
                var best:CGImage?; var score = -Double.infinity
                for fraction in [0.15,0.4,0.65,0.85] {
                    if job.isCancelled { generator.cancelAllCGImageGeneration(); return }
                    guard let frame=try? generator.copyCGImage(at:CMTime(seconds:max(0,(item.duration ?? 2)*fraction),preferredTimescale:600),actualTime:nil) else { continue }
                    let value=Self.score(frame)
                    if value > score { best=frame; score=value }
                }
                if let frame=best, !job.isCancelled {
                    bytes=NSBitmapImageRep(cgImage:frame).representation(using:.jpeg,properties:[.compressionFactor:0.78])
                    try? FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
                    if let bytes=bytes { try? bytes.write(to:url,options:.atomic) }
                }
            }
            if let bytes=bytes { self.memory.setObject(bytes as NSData,forKey:key as NSString,cost:bytes.count) }
            let result=bytes
            DispatchQueue.main.async { if !job.isCancelled { completion(result) } }
        }
        queue.addOperation(job); return job
    }
    static func score(_ image:CGImage)->Double {
        var pixels=[UInt8](repeating:0,count:32*18)
        let drawn=pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:32,height:18,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:32,height:18)); return true
        }
        guard drawn else { return 0 }
        let mean=pixels.reduce(0.0) { $0+Double($1) }/Double(pixels.count)
        let variance=pixels.reduce(0.0) { $0+pow(Double($1)-mean,2) }/Double(pixels.count)
        return sqrt(variance) + min(mean,255-mean)*0.2
    }
}
struct VideoThumbnail: View {
    let item:AudioItem
    @State private var thumbnail:NSImage?
    @State private var job:Operation?
    var body:some View {
        ZStack { Color.black.opacity(0.5); if let image=thumbnail { Image(nsImage:image).resizable().scaledToFit() } else { Image(systemName:"film").foregroundColor(.secondary) } }
            .cornerRadius(4).onAppear(perform:load).onDisappear { job?.cancel(); job=nil }
            .onChange(of:item.modified) { _,_ in load() }
            .onChange(of:item.path) { _,_ in thumbnail=nil; load() }
    }
    private func load() { job?.cancel(); job=ThumbnailService.shared.load(item) { thumbnail=$0.flatMap { NSImage(data:$0) } } }
}

struct CardPreview: View {
    let item:AudioItem
    let active:Bool
    let audio:AudioPlayback
    var body:some View {
        ZStack {
            VideoThumbnail(item:item)
            if active { ActiveCardVideo(audio:audio) }
        }.aspectRatio(16/9,contentMode:.fit).clipped()
    }
}
struct VideoCard: View {
    let group:ResultGroup
    @ObservedObject var lib:Library
    @ObservedObject var workspace:ShelfWorkspace
    let createProject:()->Void
    let audio:AudioPlayback
    let selectedID:String?
    let select:()->Void
    let sources:()->Void
    let details:()->Void
    var active:Bool { group.members.contains { $0.id == selectedID } }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            CardPreview(item:group.item,active:active,audio:audio)
                .overlay(alignment:.bottomTrailing) { Text(group.item.duration.map(clockText) ?? "—").font(.system(size:10,design:.monospaced)).padding(4).background(.black.opacity(0.65)).cornerRadius(3).padding(5).allowsHitTesting(false) }
                .contentShape(Rectangle()).onTapGesture(perform:select).help("点击选中，空格放大播放；再次空格或 Esc 关闭")
            VStack(alignment:.leading,spacing:5) {
                Text(group.item.name).font(.system(size:12,weight:.medium)).foregroundColor(active ? accent : .white).lineLimit(1).help(group.item.name)
                    .onTapGesture(perform:select)
                HStack(spacing:4) {
                    Text("\(group.item.videoWidth ?? 0)×\(group.item.videoHeight ?? 0)").font(.system(size:10,design:.monospaced)).foregroundColor(muted)
                    Spacer(minLength:0)
                    if group.members.count > 1 { Button("\(group.members.count) 来源",action:sources).font(.system(size:10)).buttonStyle(.plain).foregroundColor(accent) }
                }
                HStack(spacing:10) {
                    Text(group.item.ext).font(.system(size:10)).foregroundColor(muted)
                    Spacer(minLength:0)
                    Button(action:details) { Image(systemName:"info.circle") }.help("素材详情")
                    Button { for member in group.members { lib.update(member.id) { $0.favorite = !group.favorite } } } label:{ Image(systemName:group.favorite ? "star.fill" : "star") }.foregroundColor(group.favorite ? accent : muted).help("收藏")
                    NativeFileDrag(path:group.item.path,compact:true,enabled:group.item.online,onFinish:{ if $0 { lib.markUsed(group.item) } }).frame(width:25,height:24)
                }.buttonStyle(.plain).font(.system(size:12))
            }.padding(8)
        }.background(surface).cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius:7).stroke(active ? accent : Color.white.opacity(0.08),lineWidth:active ? 2 : 1))
            .contextMenu { ProjectBasketMenu(workspace:workspace,path:group.item.path,createProject:createProject,added:{ lib.status="已添加到项目素材篮："+$0 }); Divider(); Button("查看详情",action:details); Button("查看所有来源",action:sources); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:group.item.path)]) } }
    }
}

struct ActiveCardVideo: View {
    @ObservedObject var audio:AudioPlayback
    var body:some View { if let player=audio.videoPlayer { VideoSurface(player:player).allowsHitTesting(false) } }
}
