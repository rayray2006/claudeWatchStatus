import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity glue. Reads the session token from the
/// paired iPhone's applicationContext and hands it to the DeviceRegistrar.
final class WatchSessionBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSessionBridge()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // On activation, pull whatever session token the iPhone last posted.
        let token = session.receivedApplicationContext["sessionToken"] as? String
        Task { @MainActor in
            DeviceRegistrar.shared.setSession(token)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let token = applicationContext["sessionToken"] as? String
        Task { @MainActor in
            DeviceRegistrar.shared.setSession(token)
        }
    }
}
