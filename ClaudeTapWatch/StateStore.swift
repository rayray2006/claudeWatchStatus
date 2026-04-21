import Foundation
import WidgetKit

/// State holder backed by shared App Group UserDefaults.
/// Reads from defaults so it picks up state changes written by background push handlers.
final class StateStore: ObservableObject, @unchecked Sendable {
    static let shared = StateStore()

    @Published var currentState: TapState = .idle

    private let appGroup = "group.com.fm.claudetap"
    private let stateKey = "claude_state"

    private init() {
        refreshFromDefaults()
    }

    /// Re-read state from shared UserDefaults. Call when app becomes active.
    func refreshFromDefaults() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.synchronize()
        if let raw = defaults.string(forKey: stateKey),
           let state = TapState(rawValue: raw) {
            DispatchQueue.main.async {
                self.currentState = state
            }
        }
    }

    /// Write state to shared defaults and notify the widget.
    func updateState(_ state: TapState) {
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(state.rawValue, forKey: stateKey)
            defaults.set(Date().timeIntervalSince1970, forKey: "claude_state_time")
            defaults.synchronize()
        }
        DispatchQueue.main.async {
            self.currentState = state
            // Multiple reload triggers — system honors them as best-effort
            WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeTapCircular")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
