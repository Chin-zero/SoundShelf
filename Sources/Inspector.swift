import SwiftUI
import AppKit

struct Inspector: View {
    @ObservedObject var lib: Library
    @ObservedObject var audio: AudioPlayback
    @State private var customTag = ""
    @State private var dimension = "自定义"
    @State private var cueName = ""
    @State private var sourceNote = ""
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:17) {
                if let selected = audio.selected { details(lib.lookup[selected.id] ?? selected) }
                else {
                    VStack(spacing:14) { Image(systemName:"waveform").font(.system(size:36)).foregroundColor(accent.opacity(0.5)); Text("选一段声音").font(.headline); Text("查看来源、收藏和好用的时间点").font(.system(size:12)).foregroundColor(muted) }.frame(maxWidth:.infinity).padding(.top,100)
                }
            }.padding(18)
        }.background(surface.opacity(0.3))
            .onAppear { readDescription() }
            .onChange(of:audio.selected?.id) { _,_ in customTag = ""; cueName = ""; readDescription() }
    }
    func readDescription() {
        sourceNote = audio.selected.map { readSourceDescription(folder:URL(fileURLWithPath:$0.path).deletingLastPathComponent()) } ?? ""
    }
    @ViewBuilder func details(_ item: AudioItem) -> some View {
        let a = lib.annotation(item.id)
        HStack { Text("素材详情").font(.system(size:12)).foregroundColor(muted); Spacer(); Button { lib.update(item.id) { $0.favorite.toggle() } } label:{ Label(a.favorite ? "已收藏" : "收藏",systemImage:a.favorite ? "star.fill" : "star") }.font(.system(size:12)) }
        Text(item.name).font(.system(size:17,weight:.semibold)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
        HStack(spacing:8) { Text(item.kind); Text(item.ext); Text(item.isVideo ? "\(item.videoWidth ?? 0) × \(item.videoHeight ?? 0)" : item.sampleRate.map { String(format:"%.1f kHz",$0/1000) } ?? "参数未知"); Text(item.isVideo ? item.frameRate.map { String(format:"%.2f fps",$0) } ?? "" : item.channels.map { "\($0) ch" } ?? "") }.font(.system(size:11,design:.monospaced)).foregroundColor(muted)
        NativeFileDrag(path:item.path,enabled:item.online,onFinish:{ if $0 { lib.markUsed(item) } }).frame(height:38)
        HStack {
            Text("拖出完整原素材").font(.system(size:11)).foregroundColor(muted)
            Spacer()
            Menu {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:item.path)]) }
                Button("另存一份到文件夹…") { lib.copyToProject(item) }
                Button("复制文件路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path,forType:.string) }
            } label:{ Text("更多操作").font(.system(size:11)) }.menuStyle(.borderlessButton).fixedSize()
        }
        if !item.online { Label("素材离线，连接原始磁盘后可试听和拖入。",systemImage:"externaldrive.badge.xmark").font(.system(size:12)).foregroundColor(.orange) }
        if let error = item.metadataError { Text("读取异常：" + error).font(.system(size:11)).foregroundColor(.orange) }
        Divider()
        HStack { Text("好用的时间点").font(.system(size:13,weight:.semibold)); Spacer(); Text(clockText(audio.position)).font(.system(size:11,design:.monospaced)).foregroundColor(accent) }
        HStack { TextField("例如：鼓点进入",text:$cueName).textFieldStyle(.roundedBorder).onSubmit { addCue(item) }; Button("标记") { addCue(item) }.disabled(audio.duration <= 0) }
        if a.cues.isEmpty { Text("试听到合适的位置，点一下标记即可保存。").font(.system(size:11)).foregroundColor(muted) }
        ForEach(a.cues.sorted { $0.time < $1.time }) { cue in
            HStack {
                Button { audio.playFrom(cue.time) } label:{ Text(clockText(cue.time) + "  " + cue.title).font(.system(size:12)).foregroundColor(accent) }.buttonStyle(.plain)
                Spacer()
                Button { lib.update(item.id) { $0.cues.removeAll { $0.id == cue.id } } } label:{ Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain).foregroundColor(muted)
            }
        }
        Divider()
        Label("素材包原始分类",systemImage:"folder").font(.system(size:13,weight:.semibold))
        Text(item.folderCategory.isEmpty ? "未提供细分目录" : item.folderCategory).font(.system(size:12)).foregroundColor(accent).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
        Text(item.source).font(.system(size:11)).foregroundColor(muted).textSelection(.enabled)
        if !sourceNote.isEmpty { DisclosureGroup("查看素材包说明") { Text(sourceNote).font(.system(size:12)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.font(.system(size:12)) }
        Divider()
        DisclosureGroup("检索标签与个人标签") {
            VStack(alignment:.leading,spacing:9) {
                ForEach(lib.effectiveTags(item),id:\.self) { tag in
                    HStack { Text(tag.replacingOccurrences(of:":",with:" · ")).font(.system(size:12)); Spacer(); Button { lib.update(item.id) { $0.tags.removeAll { $0 == tag }; if item.tags.contains(tag) { $0.hiddenTags.append(tag) } } } label:{ Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain).foregroundColor(muted) }
                }
                Picker("维度",selection:$dimension) { ForEach(["自定义","场景","用途","情绪","风格","声音","材质","类别","人声","乐器","空间","听感"],id:\.self) { Text($0) } }
                HStack { TextField("添加个人标签",text:$customTag).textFieldStyle(.roundedBorder).onSubmit { addTag(item) }; Button("添加") { addTag(item) }.disabled(customTag.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            }.padding(.top,8)
        }.font(.system(size:13))
        DisclosureGroup("备注与项目分组") {
            VStack(alignment:.leading,spacing:9) {
                TextField("例如：秋季穿搭",text:Binding(get:{ lib.annotation(item.id).collection },set:{ text in lib.update(item.id) { $0.collection = text } })).textFieldStyle(.roundedBorder)
                TextEditor(text:Binding(get:{ lib.annotation(item.id).note },set:{ text in lib.update(item.id) { $0.note = text } })).font(.system(size:12)).frame(height:80).padding(5).background(surface).cornerRadius(5)
                Text("都可以通过顶部搜索找到。").font(.system(size:11)).foregroundColor(muted)
            }.padding(.top,8)
        }.font(.system(size:13))
        Text(item.path).font(.system(size:10)).foregroundColor(muted).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
    }
    func addTag(_ item: AudioItem) {
        let label = customTag.trimmingCharacters(in:.whitespacesAndNewlines); guard !label.isEmpty else { return }
        let tag = dimension + ":" + label
        lib.update(item.id) { $0.tags = Array(Set($0.tags + [tag])); $0.hiddenTags.removeAll { $0 == tag } }; customTag = ""
    }
    func addCue(_ item: AudioItem) {
        guard audio.duration > 0 else { return }
        let label = cueName.trimmingCharacters(in:.whitespacesAndNewlines), time = audio.position
        lib.update(item.id) { $0.cues.append(Cue(time:time,title:label.isEmpty ? "好用片段" : label)) }; cueName = ""
    }
}
struct SettingsPanel: View {
    @ObservedObject var lib: Library
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack { Text("目录与备份").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            Text("素材目录").font(.headline)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(lib.settings.roots,id:\.self) { root in
                        VStack(alignment:.leading,spacing:8) {
                            Text(root).font(.system(size:12)).textSelection(.enabled)
                            HStack {
                                Label(FileManager.default.fileExists(atPath:root) ? "已连接" : "离线",systemImage:"externaldrive").font(.system(size:11)).foregroundColor(muted)
                                Spacer(); Button("重新关联位置…") { lib.relocateRoot(root) }.font(.system(size:11)).disabled(lib.scanning)
                            }
                        }.padding(10).background(surface).cornerRadius(6)
                    }
                }
            }.frame(maxHeight:160)
            Button("添加素材目录…") { lib.addRoot() }
            Divider()
            Text("收藏保存在这台 Mac").font(.headline)
            Text(lib.dataFolder.path).font(.system(size:11)).foregroundColor(muted).textSelection(.enabled)
            Text("保存时自动保留历史备份。移动硬盘离线时，仍可查看索引、收藏和备注。").font(.system(size:12)).foregroundColor(muted)
            HStack { Button("导出备份…") { lib.backup() }; Button("恢复备份…") { lib.restore() } }
            Button("查看自动备份") { NSWorkspace.shared.open(lib.store.backups) }
            Divider()
            Text(lib.maintenanceStatus).font(.system(size:12)).foregroundColor(muted)
            Button("重试读取异常的音频") { lib.scan(retryErrors:true) }.disabled(lib.scanning)
        }.padding(22).background(base)
    }
}
