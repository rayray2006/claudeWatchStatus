import Foundation

enum ClaudeTapConstants {
    static let appGroupID = "group.com.fm.claudetap"

    enum Defaults {
        static let stateKey = "claude_state"
        static let stateTimeKey = "claude_state_time"
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}
