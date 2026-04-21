import Foundation
import WatchConnectivity

final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnector()

    @Published var isWatchReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendState(_ state: TapState) {
        guard WCSession.default.activationState == .activated else { return }

        let message: [String: Any] = [
            "state": state.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Use transferCurrentComplicationUserInfo for complication updates
        // This is high-priority and wakes the watch extension
        if WCSession.default.isComplicationEnabled {
            WCSession.default.transferCurrentComplicationUserInfo(message)
        } else if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isWatchReachable = reachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isWatchReachable = reachable
        }
    }
}
