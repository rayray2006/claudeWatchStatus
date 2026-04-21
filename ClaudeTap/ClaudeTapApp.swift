import SwiftUI

@main
struct ClaudeTapApp: App {
    init() {
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
