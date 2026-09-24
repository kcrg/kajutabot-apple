import SwiftUI

@main
struct KajutaBotApp: App {
    init() {
        Diagnostics.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
