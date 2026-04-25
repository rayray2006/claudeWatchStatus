import Foundation
import WatchKit

/// Keeps the watch app process alive via chained `WKExtendedRuntimeSession`
/// instances using `.physicalTherapy` (1 hour per session, runs in
/// background, no workout-style UI intrusion).
///
/// Sessions can terminate early if the OS feels memory/battery pressure
/// (`.suppressedBySystem`); chain pattern (start a new session in
/// `willExpire`) is fragile and silently breaks if the OS skips
/// `willExpire` on abrupt invalidation. Apple does not allow starting a
/// session from a background callback (Code=3), so a broken chain stays
/// broken until the user reopens the app.
///
/// Battery-saving heuristic: auto-end if no push or app activity for 30
/// minutes. Re-arms on next `applicationDidBecomeActive`.
///
/// Off by default; user opts in via Settings.
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
        print("KEEPALIVE_START_REQUESTED physical-therapy")
    }

    private func stop() {
        session?.invalidate()
        idleTimer?.invalidate()
        idleTimer = nil
        isActive = false
        print("KEEPALIVE_STOP_REQUESTED")
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
        s.invalidate()
    }
}

extension KeepAliveManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        let expirationDescription = extendedRuntimeSession.expirationDate?.description ?? "nil"
        Task { @MainActor in
            print("KEEPALIVE_STARTED expires=\(expirationDescription)")
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
            guard self.isEnabled else { return }
            self.idleTimer?.invalidate()
            self.idleTimer = nil
            let next = WKExtendedRuntimeSession()
            next.delegate = self
            next.start()
            self.session = next
            self.scheduleIdleTimer()
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        let invalidatedId = ObjectIdentifier(extendedRuntimeSession)
        let reasonRaw = reason.rawValue
        let errorDescription = error?.localizedDescription ?? "nil"
        Task { @MainActor in
            print("KEEPALIVE_INVALIDATED reason=\(reasonRaw) error=\(errorDescription)")
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
