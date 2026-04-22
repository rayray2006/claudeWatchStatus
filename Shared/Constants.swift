import Foundation
import WidgetKit

enum ClaudeTapConstants {
    static let appGroupID = "group.com.fm.claudetap"

    enum Defaults {
        static let stateKey = "claude_state"
        static let stateTimeKey = "claude_state_time"
        /// Tracks the state that was last passed to WidgetCenter.reloadAllTimelines().
        /// Lets every reload site (NSE, app, background task) cooperate via the
        /// shared App Group so we don't burn the watchOS reload budget on
        /// repeat pushes of the same state.
        static let lastReloadedStateKey = "last_reloaded_state"
    }

    enum ComplicationKind {
        static let circular = "ClaudeTapCircular"
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Reload the complication only if `newState` differs from the state we
    /// last asked the system to reload to. Safe to call from any process
    /// (app, NSE, widget) — coordinates through the shared App Group.
    ///
    /// Why this matters: watchOS budgets complication reloads (~40–50/day).
    /// Claude Code sends a `working` push on every PreToolUse, so a busy
    /// session repeats the same state many times. Un-gated reloads blow the
    /// budget and the system starts returning the placeholder (black).
    static func reloadComplicationIfChanged(_ newState: String) {
        let defaults = sharedDefaults
        let last = defaults?.string(forKey: Defaults.lastReloadedStateKey)
        guard last != newState else {
            print("RELOAD_SKIP state=\(newState) (unchanged)")
            return
        }
        defaults?.set(newState, forKey: Defaults.lastReloadedStateKey)
        WidgetCenter.shared.reloadAllTimelines()
        print("RELOAD_FIRED state=\(newState) (was \(last ?? "nil"))")
    }
}
