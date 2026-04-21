import Foundation

enum ClaudeTapConstants {
    static let appGroupID = "group.com.fm.claudetap"
    static let ntfyBaseURL = "https://ntfy.sh"
    static let ntfyWebSocketURL = "wss://ntfy.sh"

    enum Defaults {
        static let topicKey = "ntfy_topic"
        static let stateKey = "claude_state"
        static let lastTapKey = "last_tap_date"
    }

    enum ComplicationKind {
        static let circular = "ClaudeTapCircular"
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}
