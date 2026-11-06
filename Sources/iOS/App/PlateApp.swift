import SwiftUI
@main struct PlateApp: App {
    // Created exactly once for the app's lifetime. Building it inside FoundationView's init
    // re-ran Firebase setup on every view rebuild, which crashes once sync has started.
    @State private var model = PlateModel()
    var body: some Scene { WindowGroup { FoundationView(model: model) } }
}
