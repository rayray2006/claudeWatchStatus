import SwiftUI

@main
struct ClaudeTapApp: App {
    @State private var auth = AuthStore()

    init() {
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(auth: auth)
        }
    }
}
