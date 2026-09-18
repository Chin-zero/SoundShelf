import Foundation
struct SearchOptions: Codable, Equatable { var section=""; var query=""; var tags:Set<String>=[] }
let suite="soundshelf.autobasket.test."+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
defer { defaults.removePersistentDomain(forName:suite) }
let shelf=ShelfWorkspace(defaults:defaults)
shelf.create("项目A"); shelf.create("项目B")
assert(!shelf.recordDrag(paths:["/audio.wav"],project:"项目A",accepted:false))
assert(shelf.baskets["项目A"]!.isEmpty)
assert(shelf.recordDrag(paths:["/audio.wav","/video.mov"],project:"项目A",accepted:true))
assert(shelf.baskets["项目A"] == ["/audio.wav","/video.mov"])
assert(shelf.baskets["项目B"]!.isEmpty)
shelf.recordDrag(paths:["/audio.wav"],project:"项目A",accepted:true)
assert(shelf.baskets["项目A"]!.count == 2)
let reopened=ShelfWorkspace(defaults:defaults)
assert(reopened.baskets["项目A"]!.count == 2)
shelf.deleteProject("项目A")
assert(!shelf.recordDrag(paths:["/audio.wav"],project:"项目A",accepted:true))
assert(shelf.baskets["项目A"] == nil)
assert(!shelf.recordDrag(paths:[],project:"项目B",accepted:true))
print("PASS 取消不加入、批量成功加入、拖动时项目锁定、去重、持久化、已删除项目不复活、空拖拽不加入")
