import Foundation
import WatchKit

/// Keeps the watch app running long-term via chained
/// `WKExtendedRuntimeSession` instances using `physicalTherapy` (the longest
/// background-runnable reason — 1 hour per session, doesn't end on Crown
/// press, doesn't require app foreground while running).
///
/// Why this works for Cued: regular APNs alert pushes only fire haptics
/// reliably while the app is "warm" (not deep-suspended). Once a session is
/// active the app process stays alive, so `didReceiveRemoteNotification`
/// fires on every push and `playHapticDebounced` runs.
///
/// Chain pattern: each session's `willExpire` callback immediately starts a
/// new session. Apple constraint: extended runtime sessions can only be
/// started while the app is foreground/active (start from a background-task
/// callback returns Code=3). So if the chain ever breaks (process killed,
/// session start fails outside foreground), the user must reopen the app to
/// re-arm.
///
/// Battery cost: roughly 2-3× idle drain. Off by default; user opts in via
/// Settings.
@MainActor
final class KeepAliveManager: NSObject, ObservableObject {
    static let shared = KeepAliveManager()

    @Published private(set) var isActive: Bool = false

    private var session: WKExtendedRuntimeSession?

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

    /// Call from `applicationDidBecomeActive`. Starts a session if the user
    /// has the toggle on and we don't already have a running session.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        if let existing = session, existing.state == .running {
            return
        }
        startNewSession()
    }

    private func startNewSession() {
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        print("KEEPALIVE_START_REQUESTED")
    }

    private func stop() {
        session?.invalidate()
        session = nil
        isActive = false
        print("KEEPALIVE_STOP")
    }
}

extension KeepAliveManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        // Snapshot the description outside the actor hop — capturing the
        // session reference itself across actors trips strict-concurrency.
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
            let next = WKExtendedRuntimeSession()
            next.delegate = self
            next.start()
            self.session = next
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        // Capture identity (Sendable) instead of the session reference itself
        // so we can do the "was this our current session?" check on main actor
        // without crossing a non-Sendable value across actors.
        let invalidatedId = ObjectIdentifier(extendedRuntimeSession)
        let reasonRaw = reason.rawValue
        let errorDescription = error?.localizedDescription ?? "nil"
        Task { @MainActor in
            print("KEEPALIVE_INVALIDATED reason=\(reasonRaw) error=\(errorDescription)")
            // Only clear if this is the session we currently track — chained
            // sessions arrive in a sequence and the previous one invalidates
            // after the next one is already running.
            if let current = self.session, ObjectIdentifier(current) == invalidatedId {
                self.session = nil
                self.isActive = false
            }
            // If still enabled and we have no live session, attempt to
            // restart. Will fail with Code=3 if the app isn't foreground.
            if self.isEnabled, self.session == nil {
                self.startNewSession()
            }
        }
    }
}
