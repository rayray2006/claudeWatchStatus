import Foundation
import WatchConnectivity

/// iOS-side WatchConnectivity glue. Sole job: share the signed-in session
/// token with the paired Apple Watch so the Watch can authenticate to the
/// backend (register its APNs device token).
///
/// Uses `updateApplicationContext` which is persistent — the Watch receives
/// the latest context at next wake / launch regardless of reachability.
final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnector()

    @Published var isWatchReachable = false

    /// The most recently shared session token. Replays on each activation so
    /// Watch always has current state even after reinstall / reset.
    private var currentSession: String?

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push a session token to the Watch. Pass nil to signal sign-out.
    func shareSession(_ token: String?) {
        currentSession = token
        pushCurrentContext()
    }

    private func pushCurrentContext() {
        guard WCSession.default.activationState == .activated else { return }
        let context: [String: Any] = [
            "sessionToken": currentSession ?? "",
            "updatedAt": Date().timeIntervalSince1970,
        ]
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.isWatchReachable = reachable }
        // Replay the current context so newly-activated Watch picks up the session.
        pushCurrentContext()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.isWatchReachable = reachable }
    }
}
