import Foundation
import WatchKit

/// Keeps the watch app process alive via single `WKExtendedRuntimeSession`
/// instances. Reason is determined by the `WKBackgroundModes` Info.plist
/// entry — currently `physical-therapy` (1 hr/session).
///
/// No chaining: Apple's "app must be active" rule (Code=3 from start())
/// makes the willExpire-chain pattern fundamentally broken — the start
/// call in willExpire fails silently when the app is backgrounded, which
/// is almost always the case. Each session simply runs until it expires
/// (~1 hour) or until the OS suppresses it; user re-opens the app to
/// re-arm via `applicationDidBecomeActive` → `resumeIfEnabled()`.
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
        // No chaining. The chain pattern requires start() to succeed in this
        // callback context, but Apple enforces "app must be active" (Code=3)
        // which fails in the background — i.e., almost every time the chain
        // would actually be useful. Just log expiry; user re-arms by
        // re-opening the app, which fires applicationDidBecomeActive →
        // resumeIfEnabled.
        Task { @MainActor in
            print("KEEPALIVE_WILL_EXPIRE — no chain (re-open app to re-arm)")
            SessionEventLog.record(.willExpire, detail: "no chain — re-open to re-arm")
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
