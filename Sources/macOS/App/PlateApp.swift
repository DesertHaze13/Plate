import SwiftUI
import PlateCore
@main struct PlateApp: App {
    @State private var model = PlateModel()
    var body: some Scene {
        WindowGroup("Plate", id: "main") { FoundationView(model: model).frame(minWidth: 760, minHeight: 620) }
            .commands { CommandGroup(replacing: .newItem) { Button("Log a meal") { model.showCapture = true }.keyboardShortcut("n") } }
        MenuBarExtra { PlateMenu(model: model) } label: { Label("\(Int(model.store.guidance.remaining)) kcal", systemImage: "fork.knife") }
    }
}
private struct PlateMenu: View {
    let model: PlateModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("\(Int(model.store.guidance.remaining)) kcal remaining")
        Text("\(Int(model.store.todayTotal.protein)) / \(Int(model.store.effectiveTargets.nutrients.protein)) g protein")
        Divider()
        Button("Log a meal") { openWindow(id: "main"); model.showCapture = true }
        Button("Open Plate") { openWindow(id: "main") }
        Divider()
        Button("Quit Plate") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
