import Foundation
import WatchKit

/// Keeps the watch app process alive via chained `WKExtendedRuntimeSession`
/// instances. Reason is determined by the `WKBackgroundModes` Info.plist
/// entry — currently `mindfulness` (1 hr/session). To switch reasons,
/// change the Info.plist entry; this file's logic is reason-agnostic.
///
/// Sessions can terminate early via `.suppressedBySystem` (raw value 4) due
/// to undocumented OS-level pressure (memory, thermal, daily session
/// budget, Low Power Mode — Apple's docs don't say which). When that
/// happens, `willExpire` is skipped and the chain breaks silently. Apple
/// does not allow starting a session from a background callback (Code=3),
/// so a broken chain stays broken until `applicationDidBecomeActive`
/// re-arms via `resumeIfEnabled()`.
///
/// All lifecycle events go through `SessionEventLog` so they can be
/// inspected on-watch via the Keep-alive log Settings view (no Xcode
/// attachment needed for diagnosis).
@MainActor
final class KeepAliveManager: NSObject, ObservableObject {
    static let shared = KeepAliveManager()

    @Published private(set) var isActive: Bool = false

    private var session: WKExtendedRuntimeSession?
    private var idleTimer: Timer?

    /// End the session if there's no push or app activity for this long.
    /// Re-arms on next app open.
    private static let idleTimeout: TimeInterval = 30 * 60

    private static let preferenceKey = "cued.keepAliveEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferenceKey)
            if newValue {
                startNewSession()
            } else {
                stop()
            }
        }
    }

    /// Call from `applicationDidBecomeActive`. If a session is already
    /// running we just bump the idle timer; otherwise start a fresh one.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        if let s = session, s.state == .running {
            scheduleIdleTimer()
            return
        }
        startNewSession()
    }

    /// Reset the 30-minute idle timer. Called from every push handler and
    /// from `applicationDidBecomeActive`.
    func markActivity() {
        scheduleIdleTimer()
    }

    private func startNewSession() {
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        scheduleIdleTimer()
        print("KEEPALIVE_START_REQUESTED")
        SessionEventLog.record(.startRequested)
    }

    private func stop() {
        session?.invalidate()
        idleTimer?.invalidate()
        idleTimer = nil
        isActive = false
        print("KEEPALIVE_STOP_REQUESTED")
        SessionEventLog.record(.manualStop)
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard isEnabled, let s = session, s.state == .running else { return }
        let t = Timer(timeInterval: Self.idleTimeout, repeats: false) { _ in
            Task { @MainActor in
                Self.shared.handleIdleTimeout()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    private func handleIdleTimeout() {
        guard let s = session, s.state == .running else { return }
        print("KEEPALIVE_IDLE_TIMEOUT 30min — ending session")
        SessionEventLog.record(.idleTimeout, detail: "no activity for 30m")
        s.invalidate()
    }
}

private func readableInvalidationReason(_ reason: WKExtendedRuntimeSessionInvalidationReason) -> String {
    switch reason {
    case .none:              return "none"
    case .expired:           return "expired"
    case .sessionInProgress: return "sessionInProgress"
    case .error:             return "error"
    case .suppressedBySystem: return "suppressedBySystem"
    case .resignedFrontmost: return "resignedFrontmost"
    @unknown default:        return "unknown"
    }
}

extension KeepAliveManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        let expirationDescription = extendedRuntimeSession.expirationDate?.description ?? "nil"
        Task { @MainActor in
            print("KEEPALIVE_STARTED expires=\(expirationDescription)")
            SessionEventLog.record(.started, detail: "expires=\(expirationDescription)")
            self.isActive = true
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        // Chain a new session before this one expires. This callback runs
        // while the current session is still active, so start() is allowed.
        Task { @MainActor in
            print("KEEPALIVE_WILL_EXPIRE chaining")
            SessionEventLog.record(.willExpire)
            guard self.isEnabled else { return }
            self.idleTimer?.invalidate()
            self.idleTimer = nil
            let next = WKExtendedRuntimeSession()
            next.delegate = self
            next.start()
            self.session = next
            self.scheduleIdleTimer()
            SessionEventLog.record(.chained)
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        let invalidatedId = ObjectIdentifier(extendedRuntimeSession)
        let reasonRaw = reason.rawValue
        let reasonName = readableInvalidationReason(reason)
        let errorDescription = error?.localizedDescription ?? "nil"
        Task { @MainActor in
            print("KEEPALIVE_INVALIDATED reason=\(reasonRaw)(\(reasonName)) error=\(errorDescription)")
            SessionEventLog.record(
                .invalidated,
                detail: "reason=\(reasonName) error=\(errorDescription)"
            )
            if let current = self.session, ObjectIdentifier(current) == invalidatedId {
                self.session = nil
                self.isActive = false
                self.idleTimer?.invalidate()
                self.idleTimer = nil
            }
            // No auto-restart. All restart paths flow through
            // resumeIfEnabled() (called from applicationDidBecomeActive).
        }
    }
}
