import Foundation

/// File-based state store backed by a JSON file in the App Group container.
///
/// Used by every process that needs to read/write Claude's current state
/// (main watch app, complication widget extension, notification service
/// extension). Reads always hit disk so there are no cross-process cache
/// coherence problems — unlike `UserDefaults(suiteName:)` which can hold
/// stale values from another process's writes on watchOS.
enum SharedState {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ClaudeTapConstants.appGroupID)?
            .appendingPathComponent("state.json")
    }

    struct Entry {
        let state: TapState
        let date: Date
    }

    /// Write the current state and timestamp atomically.
    static func save(_ state: TapState, at date: Date = Date()) {
        guard let fileURL else { return }
        let payload: [String: Any] = [
            "state": state.rawValue,
            "time": date.timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Load the last persisted state. Returns nil if no state has been saved
    /// yet, or the file is corrupted.
    static func load() -> Entry? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["state"] as? String,
              let state = TapState(rawValue: raw)
        else { return nil }
        let t = json["time"] as? Double ?? 0
        return Entry(state: state, date: Date(timeIntervalSince1970: t))
    }
}
