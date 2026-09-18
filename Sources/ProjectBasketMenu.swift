import SwiftUI

struct ProjectBasketMenu: View {
    @ObservedObject var workspace:ShelfWorkspace
    let path:String
    let createProject:()->Void
    let added:(String)->Void
    private func contains(_ name:String)->Bool { workspace.baskets[name]?.contains(path) == true }
    private func add(_ name:String) { workspace.add([path],to:name); added(name) }
    var body:some View {
        Menu("添加到项目素材篮") {
            ForEach(workspace.baskets.keys.sorted(),id:\.self) { name in
                Button(contains(name) ? "✓ \(name)（已添加）" : name) { add(name) }.disabled(contains(name))
            }
            if !workspace.baskets.isEmpty { Divider() }
            Button("新建项目…",action:createProject)
        }
    }
}
