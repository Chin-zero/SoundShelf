import Foundation
import Combine

func matchesTagFilters(_ tags: Set<String>, filters: Set<String>) -> Bool {
    let dimensions = Dictionary(grouping: filters, by: { $0.components(separatedBy: ":").first ?? "" })
    return dimensions.values.allSatisfy { !$0.allSatisfy { !tags.contains($0) } }
}
struct SearchOptions: Equatable, Codable {
    var query = ""
    var section = "全部素材"
    var tags: Set<String> = []
    var duration = "全部时长"
    var source = "全部来源"
    var folder = "全部原始分类"
    var format = "全部格式"
    var sort = "相关度"
    var basketPaths: Set<String> = []
    var collapseDuplicates = true
}
struct ResultGroup: Identifiable {
    var id: String
    var item: AudioItem
    var members: [AudioItem]
    var favorite: Bool
}
struct PreparedAudio {
    var item: AudioItem
    var tags: Set<String>
    var annotation: Annotation
    var text: String
    var groupID: String { item.metadataError == nil ? (item.contentDigest ?? item.path) : item.path }
}
struct SearchOutput {
    var groups: [ResultGroup] = []
    var matchedFiles = 0
    var counts: [String: Int] = [:]
    var facets: [String: Int] = [:]
    var folders: [String: [String: Int]] = [:]
    var sources: [String] = []
}
func durationMatches(_ duration: Double?, _ option: String) -> Bool {
    if option == "全部时长" { return true }
    if option == "时长待解析" { return duration == nil }
    guard let d = duration else { return false }
    switch option {
    case "不到 1 秒": return d < 1
    case "1–3 秒": return d >= 1 && d < 3
    case "3–10 秒": return d >= 3 && d < 10
    case "10–60 秒": return d >= 10 && d < 60
    case "1–3 分钟": return d >= 60 && d < 180
    case "3 分钟以上": return d >= 180
    default: return true
    }
}
func runSearch(_ records: [PreparedAudio], options: SearchOptions, cancelled: () -> Bool = { false }) -> SearchOutput? {
    var output = SearchOutput()
    let aliases = ["嗖":"掠过", "呼的一声":"呼啸", "whoosh":"掠过", "脚步声":"脚步", "布料声":"布料", "没人声":"纯音乐", "无人声":"纯音乐", "轻快":"欢快"]
    let words = options.query.lowercased().split { $0.isWhitespace || $0 == "," || $0 == "，" }.map(String.init)
    let selections = Dictionary(grouping: options.tags, by: { $0.components(separatedBy: ":").first ?? "" })
    var matches: [PreparedAudio] = [], allGroups: [String: [AudioItem]] = [:]
    var facetIDs: [String: Set<String>] = [:], sources = Set<String>(), favoriteIDs = Set<String>()
    for (index, r) in records.enumerated() {
        if index % 128 == 0 && cancelled() { return nil }
        let item = r.item, a = r.annotation
        allGroups[r.groupID, default: []].append(item)
        output.counts["全部素材", default: 0] += 1; output.counts[item.kind, default: 0] += 1
        if a.favorite { output.counts["我的收藏", default: 0] += 1; favoriteIDs.insert(item.path) }
        if !a.cues.isEmpty { output.counts["片段标记", default: 0] += 1 }
        if a.lastUsed > 0 { output.counts["最近取用", default: 0] += 1 }
        if !item.online { output.counts["离线素材", default: 0] += 1 }
        if item.metadataError != nil { output.counts["读取异常", default: 0] += 1 }
        if r.tags.isEmpty && item.folderCategory.isEmpty { output.counts["未分类", default: 0] += 1 }
        switch options.section {
        case "项目素材篮": if !options.basketPaths.contains(item.path) { continue }
        case "音乐", "音效", "视频": if item.kind != options.section { continue }
        case "我的收藏": if !a.favorite { continue }
        case "片段标记": if a.cues.isEmpty { continue }
        case "最近取用": if a.lastUsed == 0 { continue }
        case "离线素材": if item.online { continue }
        case "读取异常": if item.metadataError == nil { continue }
        case "未分类": if !r.tags.isEmpty || !item.folderCategory.isEmpty { continue }
        default: break
        }
        sources.insert(item.source)
        if !item.folderCategory.isEmpty && (options.source == "全部来源" || options.source == item.source) { output.folders[item.source, default: [:]][item.folderCategory, default: 0] += 1 }
        guard options.source == "全部来源" || item.source == options.source,
              options.folder == "全部原始分类" || item.folderKey == options.folder,
              options.format == "全部格式" || item.ext == options.format,
              durationMatches(item.duration, options.duration),
              words.allSatisfy({ r.text.contains($0) || r.text.contains(aliases[$0] ?? $0) }) else { continue }
        let failed = Set(selections.compactMap { dim, tags in tags.contains(where: r.tags.contains) ? nil : dim })
        for tag in r.tags {
            let dimension = tag.components(separatedBy: ":").first ?? ""
            if failed.isEmpty || failed == [dimension] { facetIDs[tag, default: []].insert(options.collapseDuplicates ? r.groupID : item.path) }
        }
        if failed.isEmpty { matches.append(r) }
    }
    if options.section == "最近取用" { matches.sort { $0.annotation.lastUsed > $1.annotation.lastUsed } }
    else if options.sort == "相关度", !words.isEmpty {
        func score(_ r: PreparedAudio) -> Int {
            let name = r.item.name.lowercased(), query = options.query.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
            return (name == query ? 1000 : name.hasPrefix(query) ? 300 : 0) + words.reduce(0) { total, word in total + (name.contains(word) ? 80 : r.tags.contains(where: { $0.lowercased().contains(word) }) ? 40 : 10) }
        }
        matches.sort { let a=score($0), b=score($1); return a == b ? $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending : a > b }
    }
    else if options.sort == "时长" { matches.sort { ($0.item.duration ?? .infinity) < ($1.item.duration ?? .infinity) } }
    else if options.sort == "文件修改时间" { matches.sort { $0.item.modified > $1.item.modified } }
    var seen = Set<String>()
    for r in matches {
        let id = options.collapseDuplicates ? r.groupID : r.item.path
        if seen.insert(id).inserted {
            let members = options.collapseDuplicates ? allGroups[r.groupID] ?? [r.item] : [r.item]
            output.groups.append(ResultGroup(id: id, item: r.item, members: members, favorite: members.contains { favoriteIDs.contains($0.path) }))
        }
    }
    output.matchedFiles = matches.count; output.sources = sources.sorted()
    output.facets = facetIDs.mapValues(\.count)
    return output
}
final class SearchEngine: ObservableObject {
    @Published var output = SearchOutput()
    @Published var busy = false
    private let queue = DispatchQueue(label: "soundshelf.search", qos: .userInitiated)
    private var ticket: WorkTicket?
    private var cacheRevision = -1
    private var cache: [PreparedAudio] = []
    func search(items: [AudioItem], annotations: [String: Annotation], revision: Int, options: SearchOptions) {
        ticket?.cancel(); let task = WorkTicket(); ticket = task; busy = true
        queue.asyncAfter(deadline: .now() + 0.12) {
            guard !task.cancelled else { return }
            if self.cacheRevision != revision {
                var prepared: [PreparedAudio] = []; prepared.reserveCapacity(items.count)
                for (i, item) in items.enumerated() {
                    if i % 128 == 0 && task.cancelled { return }
                    let a = annotations[item.id] ?? Annotation()
                    let tags = Set(item.tags.filter { !a.hiddenTags.contains($0) } + a.tags)
                    let text = ([item.name, item.relative, item.kind, a.note, a.collection] + Array(tags) + a.cues.map(\.title)).joined(separator: " ").lowercased()
                    prepared.append(PreparedAudio(item: item, tags: tags, annotation: a, text: text))
                }
                self.cache = prepared; self.cacheRevision = revision
            }
            guard let result = runSearch(self.cache, options: options, cancelled: { task.cancelled }) else { return }
            DispatchQueue.main.async { guard !task.cancelled else { return }; self.output = result; self.busy = false }
        }
    }
}
