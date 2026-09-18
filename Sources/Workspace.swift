import Foundation
import Combine
struct SavedShelfSearch: Codable, Identifiable {
    var id = UUID(); var name: String; var options: SearchOptions
}
struct DeletedShelfProject: Codable, Identifiable {
    var id=UUID()
    var name:String
    var paths:Set<String>
    var deletedAt=Date()
}
final class ShelfWorkspace: ObservableObject {
    static let shared=ShelfWorkspace()
    private let defaults: UserDefaults
    @Published var deletedProjects:[DeletedShelfProject] { didSet { persist(deletedProjects,"deletedProjects") } }
    @Published var history: [String] { didSet { persist(history,"history") } }
    @Published var saved: [SavedShelfSearch] { didSet { persist(saved,"saved") } }
    @Published var baskets: [String:Set<String>] { didSet { persist(baskets,"baskets") } }
    @Published var current: String { didSet { defaults.set(current,forKey:"shelf.currentBasket") } }
    var paths: Set<String> { baskets[current] ?? [] }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T:Decodable>(_ key:String,_ fallback:T)->T { defaults.data(forKey:"shelf."+key).flatMap { try? JSONDecoder().decode(T.self,from:$0) } ?? fallback }
        deletedProjects=load("deletedProjects",[])
        history=load("history",[]); saved=load("saved",[]); baskets=load("baskets",["当前项目":Set<String>()]); current=defaults.string(forKey:"shelf.currentBasket") ?? "当前项目"
    }
    private func persist<T:Encodable>(_ value:T,_ key:String) { if let data=try? JSONEncoder().encode(value) { defaults.set(data,forKey:"shelf."+key) } }
    func remember(_ query:String) { let q=query.trimmingCharacters(in:.whitespacesAndNewlines); if !q.isEmpty { history=Array(([q]+history.filter { $0 != q }).prefix(12)) } }
    func save(_ options:SearchOptions) { remember(options.query); let name=([options.section,options.query]+options.tags.sorted().map { $0.components(separatedBy:":").last ?? $0 }).filter { !$0.isEmpty }.joined(separator:" · "); saved.removeAll { $0.options == options }; saved.insert(SavedShelfSearch(name:name,options:options),at:0) }
    func create(_ name:String) { if baskets[name] == nil { baskets[name]=[] }; current=name }
    func add(_ paths:[String]) { add(paths,to:current) }
    func add(_ paths:[String],to project:String) { guard baskets[project] != nil else { return }; baskets[project,default:[]].formUnion(paths) }
    @discardableResult
    func recordDrag(paths:[String],project:String,accepted:Bool)->Bool {
        guard accepted, !paths.isEmpty, baskets[project] != nil else { return false }
        add(paths,to:project); return true
    }
    func deleteProject(_ name:String) {
        guard let paths=baskets[name] else { return }
        // Save recovery data before removing the live project.
        deletedProjects.insert(DeletedShelfProject(name:name,paths:paths),at:0)
        defaults.synchronize()
        baskets.removeValue(forKey:name)
        if current == name { current=baskets.keys.sorted().first ?? "" }
    }
    func restoreProject(_ id:UUID) {
        guard let entry=deletedProjects.first(where:{ $0.id == id }) else { return }
        var name=entry.name
        var suffix=1
        while baskets[name] != nil { name=entry.name + "（恢复\(suffix)）"; suffix += 1 }
        baskets[name]=entry.paths; current=name
        defaults.synchronize()
        deletedProjects.removeAll { $0.id == id }
    }
    func remove(_ paths:[String]) { baskets[current,default:[]].subtract(paths) }
}
