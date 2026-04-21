import Foundation

/// File-based state storage that works reliably between Watch app and Widget extension.
/// UserDefaults with App Groups can be unreliable in simulators.
enum StateStore {
    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ClaudeTapConstants.appGroupID
        )
    }

    private static var stateFileURL: URL? {
        containerURL?.appendingPathComponent("claude_state.json")
    }

    static func save(state: TapState) {
        guard let url = stateFileURL else {
            // Fallback: write to documents directory
            saveFallback(state: state)
            return
        }
        let data: [String: Any] = [
            "state": state.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: url)
        }
    }

    static func load() -> TapState {
        if let url = stateFileURL, let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let stateStr = json["state"] as? String,
           let state = TapState(rawValue: stateStr) {
            return state
        }
        // Fallback
        return loadFallback()
    }

    // Fallback for when App Group container isn't available
    private static var fallbackURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("claude_state.json")
    }

    private static func saveFallback(state: TapState) {
        let data: [String: Any] = [
            "state": state.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: fallbackURL)
        }
    }

    private static func loadFallback() -> TapState {
        guard let data = try? Data(contentsOf: fallbackURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stateStr = json["state"] as? String,
              let state = TapState(rawValue: stateStr) else {
            return .idle
        }
        return state
    }
}
