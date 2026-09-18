import SwiftUI

struct PlaybackPanel: View {
    @ObservedObject var audio: AudioPlayback
    let compact: Bool
    let previous: () -> Void
    let next: () -> Void
    var body: some View {
        VStack(spacing:10) {
            if compact {
                HStack { Text(audio.selected?.name ?? "选择一个声音开始试听").font(.system(size:12,weight:.medium)).lineLimit(1); Spacer(); Image(systemName:"speaker.wave.2").foregroundColor(muted); Slider(value:$audio.volume,in:0...1).frame(width:65) }
                wave
                HStack { transport; Spacer(); loopButton }
            } else {
                HStack(spacing:18) {
                    transport
                    VStack(alignment:.leading,spacing:5) { Text(audio.selected?.name ?? "选择一个声音开始试听").font(.system(size:13,weight:.medium)).lineLimit(1); Text(audio.selected?.kind ?? "空格试听 · ↑ ↓ 切换").font(.system(size:11)).foregroundColor(muted) }.frame(width:175,alignment:.leading)
                    wave
                    loopButton
                    Image(systemName:"speaker.wave.2").foregroundColor(muted)
                    Slider(value:$audio.volume,in:0...1).frame(width:70)
                }
            }
            HStack(spacing:9) {
                Button(audio.rangeStart.map { "A " + clockText($0) } ?? "设 A 点") { audio.setA() }
                Button(audio.rangeEnd.map { "B " + clockText($0) } ?? "设 B 点") { audio.setB() }
                if audio.rangeStart != nil || audio.rangeEnd != nil { Button { audio.clearRange() } label:{ Image(systemName:"xmark.circle") }.help("清除试听区间") }
                Spacer(minLength:0)
                Text(audio.range == nil ? "A/B 区间试听" : "区间仅用于试听").font(.system(size:10)).foregroundColor(muted)
            }.font(.system(size:11)).buttonStyle(.bordered).controlSize(.small).disabled(audio.duration <= 0)
        }.padding(.horizontal,compact ? 15 : 22).padding(.vertical,13).background(surface).overlay(alignment:.top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height:1) }
    }
    var transport: some View {
        HStack(spacing:13) {
            Button(action:previous) { Image(systemName:"backward.end.fill") }.help("上一条")
            Button { audio.skip(-5) } label:{ Image(systemName:"gobackward.5") }.help("后退 5 秒")
            Button { audio.toggle() } label:{
                ZStack { Circle().fill(accent).frame(width:39,height:39); if audio.loading { ProgressView().controlSize(.small).tint(base) } else { Image(systemName:audio.playing ? "pause.fill" : "play.fill").font(.system(size:16)).foregroundColor(base) } }
            }.disabled(audio.selected == nil).help(audio.selected?.isVideo == true ? "播放／暂停 · 空格放大预览" : "播放／暂停 · 空格")
            Button { audio.skip(5) } label:{ Image(systemName:"goforward.5") }.help("前进 5 秒")
            Button(action:next) { Image(systemName:"forward.end.fill") }.help("下一条")
        }.font(.system(size:13)).buttonStyle(.plain)
    }
    var loopButton: some View {
        Button { audio.loop.toggle() } label:{ Image(systemName:"repeat").foregroundColor(audio.loop ? accent : muted).padding(6).background(audio.loop ? accent.opacity(0.12) : .clear).cornerRadius(5) }.buttonStyle(.plain).help(audio.range == nil ? "整条循环" : "A/B 区间循环")
    }
    var wave: some View {
        VStack(spacing:3) {
            if audio.selected?.isVideo == true { Slider(value:Binding(get:{audio.position},set:{audio.seek($0)}),in:0...max(0.01,audio.duration)).accessibilityLabel("视频播放进度") }
            else { WaveDisplay(peaks:audio.peaks,progress:audio.duration > 0 ? audio.position/audio.duration : 0,start:audio.rangeStart.map { $0/max(0.001,audio.duration) },end:audio.rangeEnd.map { $0/max(0.001,audio.duration) },seek:{ audio.seek($0*audio.duration) }).frame(height:compact ? 35 : 40) }
            HStack { Text(clockText(audio.position)); Spacer(); Text(audio.loadingWave ? "读取波形…" : clockText(audio.duration)) }.font(.system(size:10,design:.monospaced)).foregroundColor(muted)
        }
    }
}
struct WaveDisplay: View {
    let peaks: [Float]
    let progress: Double
    let start: Double?
    let end: Double?
    let seek: (Double) -> Void
    var body: some View {
        GeometryReader { geo in
            Canvas { context,size in
                if let a = start, let b = end, b > a { context.fill(Path(CGRect(x:CGFloat(a)*size.width,y:0,width:CGFloat(b-a)*size.width,height:size.height)),with:.color(accent.opacity(0.10))) }
                if peaks.isEmpty {
                    var line = Path(); line.move(to:CGPoint(x:0,y:size.height/2)); line.addLine(to:CGPoint(x:size.width,y:size.height/2)); context.stroke(line,with:.color(muted.opacity(0.3)),lineWidth:1)
                } else {
                    let step: CGFloat = size.width/CGFloat(peaks.count)
                    for (i,p) in peaks.enumerated() {
                        let h: CGFloat = max(2,CGFloat(p)*size.height)
                        let rect = CGRect(x:CGFloat(i)*step,y:(size.height-h)/2,width:max(1,step*0.65),height:h)
                        context.fill(Path(roundedRect:rect,cornerRadius:1),with:.color(Double(i)/Double(peaks.count) <= progress ? accent : muted.opacity(0.5)))
                    }
                }
                for marker in [start,end].compactMap({$0}) {
                    var line = Path(); let x = CGFloat(marker)*size.width; line.move(to:CGPoint(x:x,y:0)); line.addLine(to:CGPoint(x:x,y:size.height)); context.stroke(line,with:.color(.orange),lineWidth:2)
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { seek(max(0,min(1,$0.location.x/max(1,geo.size.width)))) })
        }.accessibilityLabel("音频波形，点击跳转；橙色线为 A/B 标记")
    }
}
