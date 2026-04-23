import Foundation

enum ClaudeTapConstants {
    static let appGroupID = "group.com.fm.claudetap"

    enum Defaults {
        static let stateKey = "claude_state"
        static let stateTimeKey = "claude_state_time"
    }

    enum ComplicationKind {
        static let smartStack = "ClaudeTapStatus"
    }

    /// Bundle topic used when sending PKPushType.complication pushes via APNs.
    /// Convention: <main bundle id>.complication.
    static let complicationApnsTopic = "com.fm.claudetap.watchapp.complication"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}
