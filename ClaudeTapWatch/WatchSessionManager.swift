import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSessionManager()

    @Published var currentState: TapState = .idle
    @Published var lastTapDate: Date?
    @Published var isPhoneReachable = false

    private override init() {
        super.init()
        // Load persisted state
        if let saved = ClaudeTapConstants.sharedDefaults?.string(forKey: ClaudeTapConstants.Defaults.stateKey),
           let state = TapState(rawValue: saved) {
            currentState = state
        }
        let ts = ClaudeTapConstants.sharedDefaults?.double(forKey: ClaudeTapConstants.Defaults.lastTapKey) ?? 0
        if ts > 0 { lastTapDate = Date(timeIntervalSince1970: ts) }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func handleIncoming(_ info: [String: Any]) {
        guard let stateStr = info["state"] as? String,
              let state = TapState(rawValue: stateStr) else { return }

        DispatchQueue.main.async {
            self.currentState = state

            // Persist for complication
            let defaults = ClaudeTapConstants.sharedDefaults
            defaults?.set(state.rawValue, forKey: ClaudeTapConstants.Defaults.stateKey)

            if state.needsTap {
                self.lastTapDate = Date()
                defaults?.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.lastTapKey)
                NotificationHandler.shared.triggerHaptic(for: state)
            }

            // Reload complication timeline
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isPhoneReachable = reachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isPhoneReachable = reachable
        }
    }
}
