import SwiftUI
import AppKit

let accent = Color(red:0.74,green:0.90,blue:0.46)
let base = Color(red:0.065,green:0.075,blue:0.085)
let surface = Color(red:0.10,green:0.115,blue:0.125)
let muted = Color(red:0.65,green:0.69,blue:0.70)
func tagLabel(_ tag: String) -> String { tag.split(separator:":",maxSplits:1).last.map(String.init) ?? tag }
let librarySections = ["全部素材","音乐","音效","视频","我的收藏","片段标记","最近取用","项目素材篮","未分类","离线素材","读取异常"]

@main struct SoundShelfApp: App {
    @StateObject private var library: Library
    @StateObject private var playback = AudioPlayback()
    init() {
        let configured = Bundle.main.resourceURL.flatMap { try? String(contentsOf:$0.appendingPathComponent("LibraryHome.txt"),encoding:.utf8) }?.trimmingCharacters(in:.whitespacesAndNewlines)
        let home = configured.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath:$0) : nil } ?? Bundle.main.bundleURL.deletingLastPathComponent()
        _library = StateObject(wrappedValue:Library(home:home)); NSApplication.shared.setActivationPolicy(.regular)
    }
    var body: some Scene {
        WindowGroup("声屿 · 影音素材库") {
            MainView(lib:library,audio:playback).frame(minWidth:380,minHeight:620).preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)) { _ in library.saveAnnotations() }
        }.defaultSize(width:1280,height:840).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("添加素材目录…") { library.addRoot() }.keyboardShortcut("o")
                Button("核对全部素材") { library.scan() }.keyboardShortcut("r")
            }
            CommandMenu("素材库") {
                Button("切换窄窗口") { NotificationCenter.default.post(name:Notification.Name("SoundShelfToggleCompact"),object:nil) }.keyboardShortcut("m",modifiers:[.command,.shift])
                Divider()
                Button("导出收藏备份…") { library.backup() }
                Button("恢复收藏备份…") { library.restore() }
                Button("显示本机数据目录") { NSWorkspace.shared.open(library.dataFolder) }
            }
        }
    }
}
struct MainView: View {
    @ObservedObject var lib: Library
    let audio: AudioPlayback
    @StateObject private var search = SearchEngine()
    @State private var options = SearchOptions()
    @StateObject private var workspace = ShelfWorkspace.shared
    @State private var batch = false
    @State private var checked: Set<String> = []
    @State private var batchTag = ""
    @State private var newBasket = ""
    @State private var basketType = "全部"
    @State private var newProjectPopover = false
    private var videoGrid: Bool { options.section == "视频" || (options.section == "项目素材篮" && basketType == "视频") }
    @State private var removedRecent: [String:Double] = [:]
    @State private var projectToDelete: String?
    @State private var resultWidth: CGFloat = 800
    @State private var keyboardSelection = false
    @AppStorage("videoCardSize") private var cardSize = 210.0
    @AppStorage("compactAudioRows") private var compactAudioRows = true
    private var columns: Int { max(1, Int((resultWidth-24+12)/(cardSize+12))) }
    private var checkedItems: [AudioItem] { groups.filter { checked.contains($0.id) }.map(\.item) }
    @State private var selectedID: String?
    @State private var limit = 140
    @State private var settings = false
    @State private var help = false
    @State private var moreFilters = false
    @State private var detailsSheet = false
    @State private var sourceGroup: ResultGroup?
    @State private var windowWidth: CGFloat = 1280
    @State private var playbackError: String?
    @State private var pin = false
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("autoPreview") private var autoPreview = true
    @AppStorage("collapseDuplicates") private var collapseDuplicates = true
    @FocusState private var focused: Bool
    private var groups: [ResultGroup] {
        if options.section == "项目素材篮" && basketType != "全部" { return search.output.groups.filter { $0.item.kind == basketType } }
        return search.output.groups
    }
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 760
            VStack(spacing:0) {
                toolbar(compact:compact)
                if lib.storageProtected {
                    HStack { Image(systemName:"lock.shield"); Text("收藏已保护，原文件不会被覆盖"); Spacer(); Button("恢复备份") { lib.restore() } }.font(.system(size:12)).padding(10).background(Color.orange.opacity(0.15))
                }
                HSplitView {
                    if geo.size.width >= 1000 { sidebar.frame(minWidth:170,idealWidth:185,maxWidth:225) }
                    VStack(spacing:0) {
                        if options.section == "项目素材篮" { basketHeader; if batch { workspaceBar } }
                        else { searchHeader(compact:compact); filterBar(compact:compact); workspaceBar }
                        resultList(compact:compact)
                    }.frame(minWidth:320,maxWidth:.infinity,maxHeight:.infinity)
                    .background(GeometryReader { g in Color.clear.onAppear { resultWidth=g.size.width }.onChange(of:g.size.width) { _,w in resultWidth=w } })
                    if geo.size.width >= 1060 && showInspector && options.section != "视频" && options.section != "项目素材篮" && selectedID != nil { Inspector(lib:lib,audio:audio).frame(minWidth:265,idealWidth:310,maxWidth:420) }
                }
                if selectedID != nil { PlaybackPanel(audio:audio,compact:compact,previous:{ step(-1) },next:{ step(1) }) }
                else { Text("选中素材开始预览 · 视频按空格放大 · 按住 ↗ 拖出原文件").font(.system(size:11)).foregroundColor(muted).frame(maxWidth:.infinity).padding(9).background(surface) }
            }.background(base).tint(accent)
                .onAppear { windowWidth = geo.size.width }
                .onChange(of:geo.size.width) { _,width in windowWidth = width }
        }
        .onAppear { options.collapseDuplicates = collapseDuplicates; refresh() }
        .onChange(of:basketType) { _,_ in limit=140; checked=[]; LargeVideoPreview.shared.close(); audio.clearSelection() }
        .onChange(of:options) { _,_ in limit = 140; checked=[]; refresh() }
        .onChange(of:workspace.baskets) { _,_ in if options.section == "项目素材篮" { options.basketPaths=workspace.paths } }
        .onChange(of:lib.revision) { _,_ in refresh() }
        .onChange(of:collapseDuplicates) { _,v in options.collapseDuplicates = v }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("SoundShelfDragAdded"))) { event in
            if let project=event.object as? String { lib.status="已拖出并加入项目："+project }
        }
        .onReceive(audio.$selected) { item in selectedID = item?.id }
        .onReceive(audio.$error) { playbackError = $0 }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("SoundShelfToggleCompact"))) { _ in toggleCompact() }
        .background(KeyboardHandler { event in
            if LargeVideoPreview.shared.isOpen {
                if event.keyCode == 123 || event.keyCode == 126 { step(-1); return true }
                if event.keyCode == 124 || event.keyCode == 125 { step(1); return true }
                if event.keyCode == 49 || event.keyCode == 53 { LargeVideoPreview.shared.close(); return true }
                return false
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" { focused = true; return true }
            if newProjectPopover || moreFilters || settings || help || detailsSheet || projectToDelete != nil || sourceGroup != nil || NSApp.keyWindow?.firstResponder is NSTextView { return false }
            switch event.keyCode {
            case 49:
                if let item = audio.selected, item.isVideo { LargeVideoPreview.shared.open(item,audio:audio) }
                else { audio.toggle() }
                return true
            case 125: verticalStep(1); return true
            case 126: verticalStep(-1); return true
            case 123: if videoGrid { step(-1) } else { audio.skip(-5) }; return true
            case 124: if videoGrid { step(1) } else { audio.skip(5) }; return true
            default: return false
            }
        })
        .sheet(isPresented:$settings) { SettingsPanel(lib:lib).frame(width:min(560,windowWidth-20)) }
        .sheet(isPresented:$help) { helpPanel.frame(width:min(540,windowWidth-20)) }
        .sheet(isPresented:$detailsSheet) { VStack(spacing:0) { HStack { Text("素材详情").font(.headline); Spacer(); Button("完成") { detailsSheet = false } }.padding(); Inspector(lib:lib,audio:audio) }.frame(width:min(500,windowWidth-20),height:620) }
        .sheet(item:$sourceGroup) { group in SourcePanel(group:group,lib:lib,audio:audio).frame(width:min(660,max(360,windowWidth-20)),height:540) }
        .alert("删除项目？",isPresented:Binding(get:{ projectToDelete != nil },set:{ if !$0 { projectToDelete=nil } }),presenting:projectToDelete) { name in
            Button("取消",role:.cancel) { projectToDelete=nil }
            Button("删除项目",role:.destructive) {
                workspace.deleteProject(name); options.basketPaths=workspace.paths; checked=[]; projectToDelete=nil
            }
        } message: { name in
            Text("确定将“\(name)”移到“已删除项目”吗？以后可在项目素材篮中恢复。原始素材和 Final Cut Pro 项目不受影响。")
        }
        .alert("操作提示",isPresented:Binding(get:{ lib.error != nil || playbackError != nil },set:{ if !$0 { lib.error = nil; audio.error = nil; playbackError = nil } })) {
            Button("知道了") { lib.error = nil; audio.error = nil; playbackError = nil }
        } message: { Text(lib.error ?? playbackError ?? "") }
    }
    func toolbar(compact: Bool) -> some View {
        HStack(spacing:12) {
            Image(systemName:"waveform.circle.fill").foregroundColor(accent).font(.system(size:23))
            Text("声屿").font(.system(size:17,weight:.semibold))
            if !compact { Text("影音素材库").font(.system(size:12)).foregroundColor(muted) }
            Spacer()
            if compact { Button { pin.toggle(); NSApp.keyWindow?.level = pin ? .floating : .normal } label:{ Image(systemName:pin ? "pin.fill" : "pin") }.help("窗口置顶") }
            Button { toggleCompact() } label:{ Image(systemName:compact ? "arrow.up.left.and.arrow.down.right" : "sidebar.left") }.help(compact ? "展开素材库" : "窄窗口 · 与 FCP 并排使用")
            Button {
                if windowWidth < 1060 || options.section == "视频" || options.section == "项目素材篮" { detailsSheet = true } else { showInspector.toggle() }
            } label:{ Image(systemName:"sidebar.right") }.help("显示／隐藏详情")
            Menu {
                Toggle("选中即预览",isOn:$autoPreview)
                Toggle("紧凑音频列表",isOn:$compactAudioRows)
                Toggle("折叠内容相同的文件",isOn:$collapseDuplicates)
                Divider()
                Button("核对全部素材") { lib.scan() }
                Button("添加素材目录…") { lib.addRoot() }
                Button("目录与备份…") { settings = true }
                Button("使用指南") { help = true }
            } label:{ Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
        }.buttonStyle(.plain).padding(.horizontal,18).padding(.top,25).padding(.bottom,7).background(surface.opacity(0.6))
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:4) {
            Text("素材与收藏").font(.system(size:11)).foregroundColor(muted).padding(.horizontal,15).padding(.top,18).padding(.bottom,8)
            ForEach(librarySections,id:\.self) { title in
                Button { setSection(title) } label:{
                    HStack {
                        Image(systemName:sectionIcon(title)).frame(width:18)
                        Text(title).font(.system(size:12))
                        Spacer()
                        Text((title == "项目素材篮" ? workspace.paths.count : (search.output.counts[title] ?? 0)).formatted()).font(.system(size:10,design:.monospaced)).foregroundColor(muted)
                    }.padding(.horizontal,10).padding(.vertical,10).background(options.section == title ? accent.opacity(0.10) : .clear).cornerRadius(7).foregroundColor(options.section == title ? accent : .white.opacity(0.85))
                }.buttonStyle(.plain).padding(.horizontal,7)
            }
            Spacer()
            Button { lib.addRoot() } label:{ Label("添加素材目录",systemImage:"folder.badge.plus").font(.system(size:12)).frame(maxWidth:.infinity) }.padding(.horizontal,12)
            HStack { Button { settings = true } label:{ Image(systemName:"gearshape") }; Text("本机保存 · v2.5").font(.system(size:10)).foregroundColor(muted); Spacer() }.buttonStyle(.plain).padding(16)
        }.background(surface.opacity(0.25))
    }
    func sectionIcon(_ title: String) -> String {
        ["全部素材":"square.stack.3d.up","音乐":"music.note","音效":"waveform","视频":"film","我的收藏":"star","片段标记":"bookmark","最近取用":"clock","未分类":"tag","离线素材":"externaldrive.badge.xmark","读取异常":"exclamationmark.circle"][title] ?? "folder"
    }
    func setSection(_ title: String) { if title != options.section { LargeVideoPreview.shared.close(); audio.clearSelection() }; checked = []; options.basketPaths = workspace.paths; options.section = title; options.tags = []; options.source = "全部来源"; options.folder = "全部原始分类" }
    func searchHeader(compact: Bool) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                if windowWidth < 1000 {
                    Menu { ForEach(librarySections,id:\.self) { title in Button(title) { setSection(title) } } } label:{ Label(options.section,systemImage:sectionIcon(options.section)).font(.system(size:15,weight:.semibold)) }.menuStyle(.borderlessButton).fixedSize()
                } else { Text(options.section).font(.system(size:23,weight:.semibold)) }
                Spacer()
                Toggle("选中即预览",isOn:$autoPreview).toggleStyle(.checkbox).font(.system(size:11)).foregroundColor(muted)
            }
            HStack(spacing:9) {
                Image(systemName:"magnifyingglass").foregroundColor(accent)
                TextField(compact ? "搜索素材、用途、备注" : "搜索名称、用途、标签、备注…",text:$options.query).textFieldStyle(.plain).font(.system(size:14)).focused($focused).onSubmit { workspace.remember(options.query) }
                if !options.query.isEmpty { Button { options.query = "" } label:{ Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(muted) }
            }.padding(11).background(surface).cornerRadius(8).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.white.opacity(0.09)))
        }.padding(.horizontal,compact ? 14 : 20).padding(.top,10).padding(.bottom,8)
    }
    var basketHeader: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                if windowWidth < 1000 { Menu { ForEach(librarySections,id:\.self) { title in Button(title) { setSection(title) } } } label:{ Image(systemName:"sidebar.left") }.menuStyle(.borderlessButton).fixedSize() }
                Menu {
                    ForEach(workspace.baskets.keys.sorted(),id:\.self) { name in Button(name) { workspace.current=name; options.basketPaths=workspace.paths; checked=[]; audio.clearSelection() } }
                } label:{ Label(workspace.current.isEmpty ? "选择项目" : workspace.current,systemImage:"tray").font(.system(size:15,weight:.semibold)).lineLimit(1) }.menuStyle(.borderlessButton).frame(maxWidth:190)
                Button { newProjectPopover=true } label:{ Image(systemName:"plus") }.help("新建项目").accessibilityLabel("新建项目")
                    .popover(isPresented:$newProjectPopover) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("新建项目").font(.headline)
                            TextField("项目名称",text:$newBasket).onSubmit { createBasket() }
                            HStack { Button("取消") { newProjectPopover=false; newBasket="" }; Spacer(); Button("创建") { createBasket() }.disabled(newBasket.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                        }.padding(18).frame(width:270)
                    }
                if workspace.baskets[workspace.current] != nil { Button { projectToDelete=workspace.current } label:{ Image(systemName:"xmark") }.foregroundColor(muted).help("删除项目（需确认）").accessibilityLabel("删除当前项目") }
                if !workspace.deletedProjects.isEmpty {
                    Menu {
                        ForEach(workspace.deletedProjects) { entry in
                            Button("恢复“\(entry.name)” · \(entry.paths.count) 个素材") {
                                workspace.restoreProject(entry.id); options.basketPaths=workspace.paths; checked=[]; basketType="全部"; audio.clearSelection()
                            }
                        }
                    } label:{ Image(systemName:"arrow.uturn.backward") }.menuStyle(.borderlessButton).fixedSize().help("已删除项目 · 点击恢复").accessibilityLabel("已删除项目")
                }
                HStack(spacing:6) {
                    Image(systemName:"magnifyingglass").foregroundColor(muted)
                    TextField("搜索项目素材",text:$options.query).textFieldStyle(.plain).focused($focused)
                    if !options.query.isEmpty { Button { options.query="" } label:{ Image(systemName:"xmark.circle.fill") } }
                }.padding(8).background(surface).cornerRadius(6)
                Button { moreFilters=true } label:{ Image(systemName:hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }.help("筛选项目素材").accessibilityLabel("筛选项目素材")
                    .popover(isPresented:$moreFilters) {
                        VStack(alignment:.leading,spacing:12) {
                            HStack { ForEach(primaryDimensions,id:\.self) { tagMenu($0) } }
                            folderMenu
                            Picker("时长",selection:$options.duration) { ForEach(["全部时长","不到 1 秒","1–3 秒","3–10 秒","10–60 秒","1–3 分钟","3 分钟以上","时长待解析"],id:\.self) { Text($0) } }
                            advancedFilters
                            Button("清除筛选") { options.tags=[]; options.source="全部来源"; options.folder="全部原始分类"; options.format="全部格式"; options.duration="全部时长" }
                        }.padding(16).frame(width:350)
                    }
            }.buttonStyle(.plain)
            HStack(spacing:6) {
                ForEach(["全部","视频","音乐","音效"],id:\.self) { kind in
                    let count=kind == "全部" ? search.output.groups.count : search.output.groups.filter { $0.item.kind == kind }.count
                    Button { basketType=kind } label:{ Text("\(kind) \(count)").font(.system(size:12,weight:basketType == kind ? .semibold : .regular)).padding(.horizontal,12).padding(.vertical,7).background(basketType == kind ? accent.opacity(0.15) : .clear).foregroundColor(basketType == kind ? accent : muted).cornerRadius(6) }.buttonStyle(.plain)
                }
                Spacer(minLength:0)
            }
        }.padding(14)
    }
    func createBasket() {
        let name=newBasket.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        workspace.create(name); options.basketPaths=workspace.paths; newBasket=""; newProjectPopover=false; basketType="全部"; checked=[]; audio.clearSelection()
    }
    var workspaceBar: some View {
        VStack(spacing:6) {
            if options.section != "项目素材篮" { HStack {
                Menu {
                    Button("保存当前搜索与筛选") { workspace.save(options) }
                    ForEach(workspace.saved) { entry in Button(entry.name) { options=entry.options; options.basketPaths=workspace.paths } }
                    if !workspace.saved.isEmpty { Divider(); Button("清空已保存筛选") { workspace.saved=[] } }
                    Divider()
                    ForEach(workspace.history,id:\.self) { query in Button(query) { options.query=query } }
                    Button("清空搜索记录") { workspace.history=[] }
                } label: { Label("常用搜索",systemImage:"clock.arrow.circlepath") }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Menu {
                    ForEach(workspace.baskets.keys.sorted(),id:\.self) { name in Button(name) { workspace.current=name } }
                    Divider()
                    Button("管理项目…") { setSection("项目素材篮") }
                } label: { Label(workspace.current.isEmpty ? "选择归入项目" : "拖出归入："+workspace.current,systemImage:"tray").lineLimit(1) }.menuStyle(.borderlessButton).fixedSize().help("成功拖出后自动加入此项目，取消拖拽不加入")
            }
            }
            if batch {
                HStack {
                    Text("已选 \(checked.count)")
                    Button("全选结果") { checked=Set(groups.map(\.id)) }
                    Menu("批量操作") {
                        Button("收藏") { lib.updateMany(checkedItems.map(\.id)) { $0.favorite=true } }
                        Button("取消收藏") { lib.updateMany(checkedItems.map(\.id)) { $0.favorite=false } }
                        Button("加入“\(workspace.current)”") { workspace.add(checkedItems.map(\.path)); options.basketPaths=workspace.paths }.disabled(workspace.baskets[workspace.current] == nil)
                        if options.section == "项目素材篮" { Button("移出素材篮") { workspace.remove(checkedItems.map(\.path)); options.basketPaths=workspace.paths; checked=[] } }
                    }.disabled(checked.isEmpty)
                    TextField("批量标签",text:$batchTag).frame(maxWidth:130)
                    Button("添加") { let t=batchTag.trimmingCharacters(in:.whitespacesAndNewlines); if !t.isEmpty { lib.updateMany(checkedItems.map(\.id)) { if !$0.tags.contains("自定义:"+t) { $0.tags.append("自定义:"+t) } }; batchTag="" } }.disabled(checked.isEmpty || batchTag.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    if let first=checkedItems.first {
                        NativeFileDrag(path:first.path,additionalPaths:Array(checkedItems.dropFirst().map(\.path)),compact:true,enabled:checkedItems.allSatisfy(\.online),onFinish:{ success in if success { for item in checkedItems { lib.markUsed(item) } } }).frame(width:32,height:25)
                    }
                }
            }
        }.font(.system(size:11)).padding(.horizontal,16).padding(.bottom,7)
    }
    var primaryDimensions: [String] { options.section == "视频" ? ["类别","风格","画幅"] : options.section == "音乐" ? ["场景","情绪","风格"] : options.section == "音效" ? ["声音","类别","材质"] : ["类别","场景","情绪"] }
    var allDimensions: [String] { ["画幅","类别","声音","场景","用途","情绪","风格","材质","听感","空间","时间形态","乐器","人声","能量","节奏","自定义"] }
    func tagMenu(_ dimension: String) -> some View {
        let tags = Set(search.output.facets.keys).union(options.tags).filter { $0.hasPrefix(dimension + ":") }.sorted()
        return Menu {
            if tags.isEmpty { Text("当前条件下暂无可选项") }
            ForEach(tags,id:\.self) { tag in
                let count = search.output.facets[tag] ?? 0
                Button((options.tags.contains(tag) ? "✓ " : "") + tagLabel(tag) + "  (\(count))") {
                    if options.tags.contains(tag) { options.tags.remove(tag) } else { options.tags.insert(tag) }
                }.disabled(count == 0 && !options.tags.contains(tag))
            }
        } label:{ Text(dimension + (options.tags.contains { $0.hasPrefix(dimension + ":") } ? " •" : "")).font(.system(size:12)) }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal,9).padding(.vertical,7).background(surface).cornerRadius(5)
    }
    func filterBar(compact: Bool) -> some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(spacing:7) {
                ForEach(primaryDimensions,id:\.self) { tagMenu($0) }
                Spacer(minLength:0)
                Button { moreFilters.toggle() } label:{ Label("更多",systemImage:"line.3.horizontal.decrease") }.font(.system(size:11)).buttonStyle(.plain)
                    .popover(isPresented:$moreFilters) { advancedFilters.frame(width:330).padding(18) }
            }
            HStack(spacing:9) {
                folderMenu
                Spacer(minLength:0)
                Menu {
                    ForEach(["全部时长","不到 1 秒","1–3 秒","3–10 秒","10–60 秒","1–3 分钟","3 分钟以上","时长待解析"],id:\.self) { value in Button(value) { options.duration = value } }
                } label:{ Text(options.duration).font(.system(size:11)) }.menuStyle(.borderlessButton).fixedSize()
                if hasFilters { Button("重置") { let section = options.section; options = SearchOptions(); options.section = section; options.collapseDuplicates = collapseDuplicates }.font(.system(size:11)).buttonStyle(.plain).foregroundColor(muted) }
            }
            if !options.tags.isEmpty {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:5) { ForEach(options.tags.sorted(),id:\.self) { tag in Button { options.tags.remove(tag) } label:{ Text(tagLabel(tag) + " ×").font(.system(size:11)).padding(.horizontal,8).padding(.vertical,5).background(accent.opacity(0.12)).cornerRadius(4) }.buttonStyle(.plain).foregroundColor(accent) } }
                }
            }
        }.padding(.horizontal,compact ? 14 : 20).padding(.bottom,12)
    }
    var hasFilters: Bool { !options.tags.isEmpty || !options.query.isEmpty || options.folder != "全部原始分类" || options.source != "全部来源" || options.duration != "全部时长" || options.format != "全部格式" }
    var folderMenu: some View {
        Menu {
            Button("全部原始分类") { options.folder = "全部原始分类" }
            ForEach(search.output.folders.keys.sorted(),id:\.self) { source in
                Menu(source) {
                    ForEach((search.output.folders[source] ?? [:]).keys.sorted(),id:\.self) { category in
                        Button(category + " (\(search.output.folders[source]?[category] ?? 0))") { options.folder = source + " ▸ " + category }
                    }
                }
            }
        } label:{ Label(options.folder == "全部原始分类" ? "来源分类" : options.folder.components(separatedBy:" ▸ ").last ?? options.folder,systemImage:"folder").font(.system(size:11)).lineLimit(1) }.menuStyle(.borderlessButton).foregroundColor(accent)
    }
    var advancedFilters: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("更多筛选").font(.headline)
            Text("同类选项满足任意一种；不同类别同时满足。").font(.system(size:11)).foregroundColor(muted)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:9) { ForEach(allDimensions.filter { !primaryDimensions.contains($0) },id:\.self) { tagMenu($0) } }
            Divider()
            Picker("来源",selection:$options.source) { Text("全部来源").tag("全部来源"); ForEach(search.output.sources,id:\.self) { Text($0).tag($0) } }.onChange(of:options.source) { _,_ in options.folder = "全部原始分类" }
            Picker("格式",selection:$options.format) { ForEach(["全部格式","WAV","MP3","AIFF","AIF","M4A","FLAC","AAC","CAF","OGG","MP4","MOV","M4V","AVI","MKV","WEBM"],id:\.self) { Text($0) } }
            Toggle("折叠内容相同的文件",isOn:$collapseDuplicates)
            Text("只折叠已通过内容校验的副本，保留每个来源和原文件。").font(.system(size:11)).foregroundColor(muted)
        }.font(.system(size:12))
    }
    func resultList(compact: Bool) -> some View {
        VStack(spacing:0) {
            HStack {
                Text("\(groups.count.formatted()) 个结果").font(.system(size:12,weight:.medium))
                if options.section != "项目素材篮" && search.output.matchedFiles > groups.count { Text("／\(search.output.matchedFiles.formatted()) 文件").font(.system(size:11)).foregroundColor(muted) }
                if search.busy { ProgressView().controlSize(.mini) }
                Spacer(minLength:0)
                if videoGrid {
                    Picker("缩略图",selection:$cardSize) { Text("小").tag(160.0); Text("中").tag(210.0); Text("大").tag(280.0) }.labelsHidden().frame(width:75)
                }
                Button(batch ? "完成多选" : "多选") { batch.toggle(); checked=[] }.font(.system(size:11))
                Menu { ForEach(["相关度","名称","时长","文件修改时间"],id:\.self) { value in Button(value) { options.sort = value } } } label:{ Image(systemName:"arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize().help("排序：" + options.sort)
            }.padding(.horizontal,compact ? 14 : 20).padding(.vertical,10).background(Color.white.opacity(0.025))
            if groups.isEmpty {
                VStack(spacing:12) {
                    Image(systemName:lib.scanning || search.busy ? "externaldrive" : "magnifyingglass").font(.system(size:30)).foregroundColor(muted)
                    Text(lib.scanning || search.busy ? "正在整理结果…" : "没有匹配的素材").font(.system(size:15,weight:.medium))
                    Text("试试减少筛选条件，或切换来源分类。").font(.system(size:12)).foregroundColor(muted)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if videoGrid {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:cardSize),spacing:12)],spacing:12) {
                                ForEach(Array(groups.prefix(limit))) { group in
                                    VideoCard(group:group,lib:lib,workspace:workspace,createProject:{ setSection("项目素材篮"); newProjectPopover=true },audio:audio,selectedID:selectedID,select:{ choose(group) },sources:{ sourceGroup = group },details:{ audio.select(group.item,autoplay:false); detailsSheet = true })
                                        .overlay(alignment:.topLeading) { if batch { Image(systemName:checked.contains(group.id) ? "checkmark.circle.fill" : "circle").foregroundColor(accent).padding(8).background(.black.opacity(0.7)).allowsHitTesting(false) } }
                                    .id(group.id)
                                        .onAppear { if group.id == groups.prefix(limit).last?.id, limit < groups.count { limit += 100 } }
                                }
                            }.padding(12)
                        } else { LazyVStack(spacing:1) {
                            ForEach(Array(groups.prefix(limit))) { group in
                                ResultRow(basketRow:options.section == "项目素材篮",removeRecent:options.section == "最近取用" ? { removeRecent(group) } : nil,group:group,lib:lib,workspace:workspace,createProject:{ setSection("项目素材篮"); newProjectPopover=true },audio:audio,selectedID:selectedID,select:{ choose(group) },sources:{ sourceGroup = group })
                                    .overlay(alignment:.leading) { if batch { Image(systemName:checked.contains(group.id) ? "checkmark.circle.fill" : "circle").foregroundColor(accent).background(base).allowsHitTesting(false) } }
                                    .id(group.id)
                                    .onAppear { if group.id == groups.prefix(limit).last?.id, limit < groups.count { limit += 100 } }
                            }
                        }
                        }
                    }.onChange(of:selectedID) { _,id in
                        if keyboardSelection, let id = id, let group = groups.first(where:{ $0.members.contains { $0.id == id } }) { proxy.scrollTo(group.id,anchor:.center); keyboardSelection = false }
                    }
                }
            }
            HStack(spacing:6) {
                Circle().fill(lib.scanning ? Color.orange : accent).frame(width:5,height:5)
                if options.section == "最近取用", !removedRecent.isEmpty { Button("撤销移除") { undoRecentRemoval() }.font(.system(size:11)).buttonStyle(.plain).foregroundColor(accent) }
                Text(lib.status).font(.system(size:10)).foregroundColor(muted).lineLimit(1).help(lib.status + "\n" + lib.maintenanceStatus)
                Spacer(minLength:0)
            }.padding(.horizontal,14).padding(.vertical,9)
        }
    }
    func removeRecent(_ group:ResultGroup) {
        guard !lib.storageProtected else { lib.error="收藏处于保护模式，请先恢复有效备份。"; return }
        removedRecent=Dictionary(uniqueKeysWithValues:group.members.compactMap { item in
            let time=lib.annotation(item.id).lastUsed; return time > 0 ? (item.id,time) : nil
        })
        lib.updateMany(Array(removedRecent.keys)) { $0.lastUsed=0 }
        if group.members.contains(where:{ $0.id == selectedID }) { LargeVideoPreview.shared.close(); audio.clearSelection() }
        lib.status="已从最近取用移除："+group.item.name
    }
    func undoRecentRemoval() {
        guard !lib.storageProtected else { return }
        for (id,time) in removedRecent where lib.annotation(id).lastUsed == 0 { lib.update(id) { $0.lastUsed=time } }
        removedRecent=[:]; lib.status="已恢复最近取用记录"
    }
    func choose(_ group: ResultGroup) {
        if batch { if checked.contains(group.id) { checked.remove(group.id) } else { checked.insert(group.id) } }
        else { select(group.item) }
    }
    func select(_ item: AudioItem) { focused = false; NSApp.keyWindow?.makeFirstResponder(nil); audio.select(item,autoplay:autoPreview) }
    func verticalStep(_ direction:Int) { step(direction * (videoGrid ? columns : 1)) }
    func step(_ delta: Int) {
        guard !groups.isEmpty else { return }
        let current = groups.firstIndex { $0.members.contains { $0.id == selectedID } } ?? (delta > 0 ? -1 : 1)
        let next = min(max(current+delta,0),groups.count-1)
        guard next != current else { return }
        limit = max(limit,next+20); keyboardSelection = true
        if LargeVideoPreview.shared.isOpen && groups[next].item.isVideo { audio.select(groups[next].item,autoplay:false); LargeVideoPreview.shared.open(groups[next].item,audio:audio,replace:true) }
        else { LargeVideoPreview.shared.close(); select(groups[next].item) }
    }
    func refresh() { search.search(items:lib.items,annotations:lib.annotations,revision:lib.revision,options:options) }
    func toggleCompact() {
        guard let window = NSApp.keyWindow else { return }
        let compact = window.frame.width >= 760
        let size = compact ? NSSize(width:420,height:760) : NSSize(width:1280,height:840)
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect:NSRect(origin:.zero,size:size)); frame.origin = NSPoint(x:window.frame.minX,y:top-frame.height)
        if let screen = window.screen { frame.size.width = min(frame.width,screen.visibleFrame.width); frame.size.height = min(frame.height,screen.visibleFrame.height); frame.origin.x = max(screen.visibleFrame.minX,min(frame.minX,screen.visibleFrame.maxX-frame.width)); frame.origin.y = max(screen.visibleFrame.minY,frame.minY) }
        window.setFrame(frame,display:true,animate:true)
    }
    var helpPanel: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("更快找到、听到、用到").font(.title2.bold())
            Text("• 窄窗口：右上角切换，可放在 FCP 旁边；也可以直接拖动窗口边缘调整宽度。")
            Text("• 筛选：同一维度满足任意一种，不同维度同时满足。括号内是可匹配的声音数量。")
            Text("• 重复素材：内容相同的文件折叠显示，点击“多个来源”查看原始合集。原文件保留。")
            Text("• 音频：空格播放／暂停，上下切换，左右跳转 5 秒。视频：方向键按网格切换，空格放大，预览内左右切换，Esc 关闭。")
            Text("• 多选：点击多选，再点素材卡片或行；可批量收藏、加标签、加入项目素材篮，或拖出选中的原文件。")
            Text("• 本机保存：索引、收藏和备注保存在本机，自动备份位于数据目录的 Backups。硬盘未连接时仍可查阅。")
            Text("• 文件位置改变：同盘改名可自动跟随；磁盘或根目录变化时，到目录与备份中重新关联。")
            Button("完成") { help = false }.frame(maxWidth:.infinity,alignment:.trailing)
        }.font(.system(size:13)).padding(24)
    }
}

struct ResultRow: View {
    var basketRow = false
    var removeRecent: (() -> Void)? = nil
    @AppStorage("compactAudioRows") private var compactRows = true
    let group: ResultGroup
    @ObservedObject var lib: Library
    @ObservedObject var workspace: ShelfWorkspace
    let createProject: () -> Void
    let audio: AudioPlayback
    let selectedID: String?
    let select: () -> Void
    let sources: () -> Void
    var selected: Bool { group.members.contains { $0.id == selectedID } }
    var body: some View {
        HStack(spacing:9) {
            Button { audio.select(group.item,autoplay:true) } label:{
                if group.item.isVideo { VideoThumbnail(item:group.item).frame(width:basketRow ? 40 : 72,height:basketRow ? 30 : 44) } else if selected { SelectedPlayIcon(audio:audio) } else { Image(systemName:group.item.kind == "音乐" ? "music.note" : "waveform").foregroundColor(muted).frame(width:30,height:34) }
            }.buttonStyle(.plain).help("预览")
            VStack(alignment:.leading,spacing:5) {
                Text(group.item.name).font(.system(size:13,weight:selected ? .semibold : .regular)).foregroundColor(selected ? accent : .white.opacity(0.93)).lineLimit(1)
                HStack(spacing:6) {
                    Text(group.item.kind).font(.system(size:10,weight:.medium)).foregroundColor(group.item.isVideo ? .cyan : accent)
                    Text(group.item.ext).font(.system(size:10,design:.monospaced)).foregroundColor(muted)
                    if group.members.count > 1 { Button("\(group.members.count) 个来源") { sources() }.buttonStyle(.plain).font(.system(size:11)).foregroundColor(accent) }
                    else { Text(lib.effectiveTags(group.item).prefix(2).map(tagLabel).joined(separator:" · ")).font(.system(size:11)).foregroundColor(muted).lineLimit(1) }
                }
                if !compactRows && !basketRow { Text(group.item.folderCategory).font(.system(size:10)).foregroundColor(muted.opacity(0.85)).lineLimit(1).help(group.item.folderKey) }
            }
            Spacer(minLength:0)
            VStack(alignment:.trailing,spacing:4) { Text(group.item.duration.map(clockText) ?? "—").font(.system(size:11,design:.monospaced)); if !group.item.online { Text("离线").font(.system(size:10)).foregroundColor(.orange) } }
            NativeFileDrag(path:group.item.path,compact:true,enabled:group.item.online,onFinish:{ if $0 { lib.markUsed(group.item) } }).frame(width:29,height:31)
            Button {
                for member in group.members { lib.update(member.id) { $0.favorite = !group.favorite } }
            } label:{ Image(systemName:group.favorite ? "star.fill" : "star").foregroundColor(group.favorite ? accent : muted).font(.system(size:12)) }.buttonStyle(.plain).help("收藏")
            if let removeRecent=removeRecent {
                Button(action:removeRecent) { Image(systemName:"xmark").font(.system(size:11)).foregroundColor(muted).frame(width:24,height:28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("仅从最近取用移除，不删除原文件或项目素材").accessibilityLabel("从最近取用移除“\(group.item.name)”")
            }
        }.frame(height:basketRow ? 38 : nil).padding(.horizontal,13).padding(.vertical,(compactRows || basketRow) ? 6 : 12).background(selected ? accent.opacity(0.07) : Color.white.opacity(0.012))
            .overlay(alignment:.leading) { if selected { Rectangle().fill(accent).frame(width:2) } }
            .contentShape(Rectangle()).onTapGesture(perform:select)
            .contextMenu {
                ProjectBasketMenu(workspace:workspace,path:group.item.path,createProject:createProject,added:{ lib.status="已添加到项目素材篮："+$0 })
                Divider()
                Button("查看所有来源") { sources() }
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:group.item.path)]) }
                Button("另存一份到文件夹…") { lib.copyToProject(group.item) }
            }
    }
}
struct SelectedPlayIcon: View {
    @ObservedObject var audio: AudioPlayback
    var body: some View { Image(systemName:audio.playing ? "pause.fill" : "play.fill").foregroundColor(accent).frame(width:30,height:34).background(accent.opacity(0.1)).cornerRadius(5) }
}
struct SourcePanel: View {
    let group: ResultGroup
    @ObservedObject var lib: Library
    let audio: AudioPlayback
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("\(group.members.count) 个文件来源").font(.headline); Spacer(); Button("完成") { dismiss() } }
            Text("内容相同，保留各自的原始分类与备注。").font(.system(size:12)).foregroundColor(muted)
            ScrollView {
                VStack(spacing:12) {
                    ForEach(group.members) { item in
                        VStack(alignment:.leading,spacing:8) {
                            Text(item.folderCategory.isEmpty ? item.name : item.folderCategory).font(.system(size:13,weight:.medium)).textSelection(.enabled)
                            Text(item.path).font(.system(size:11)).foregroundColor(muted).textSelection(.enabled)
                            HStack { Button("试听") { audio.select(item,autoplay:true) }; Button("显示原文件") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:item.path)]) }; Spacer(); NativeFileDrag(path:item.path,compact:true,enabled:item.online,onFinish:{ if $0 { lib.markUsed(item) } }).frame(width:34,height:30) }
                        }.padding(12).background(surface).cornerRadius(7)
                    }
                }
            }
        }.padding(20).background(base)
    }
}
struct KeyboardHandler: NSViewRepresentable {
    let handler: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView { context.coordinator.handler = handler; return NSView() }
    func updateNSView(_ view: NSView,context: Context) { context.coordinator.handler = handler }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var handler: ((NSEvent) -> Bool)?; var monitor: Any?
        init() { monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] e in self?.handler?(e) == true ? nil : e } }
        deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
    }
}
