import Foundation
import HealthKit
import WatchKit

/// Keeps the watch app process alive long-term using `HKWorkoutSession` with
/// `HKWorkoutActivityType.other`. This is the only watchOS API that grants
/// reliable indefinite background runtime to a non-fitness app — chained
/// `WKExtendedRuntimeSession` instances were tried previously and proved
/// fragile (sessions terminated early due to `.suppressedBySystem`,
/// `willExpire` callback often skipped, no recovery from background).
///
/// Cost: while a session is active the watch face shows the green workout
/// indicator, and battery drain is roughly 5-10× idle. We collect no
/// samples (no `HKLiveWorkoutBuilder`, no HR queries) — the session exists
/// purely for its side effect of keeping the app process resident so
/// `didReceiveRemoteNotification` fires for every push and our explicit
/// `WKInterfaceDevice.play(_:)` runs.
///
/// Off by default; user opts in via Settings.
@MainActor
final class KeepAliveManager: NSObject, ObservableObject {
    static let shared = KeepAliveManager()

    @Published private(set) var isActive: Bool = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    private static let preferenceKey = "cued.keepAliveEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferenceKey)
            if newValue {
                Task { await startSession() }
            } else {
                stop()
            }
        }
    }

    /// Call from `applicationDidBecomeActive`. Workout sessions survive
    /// indefinite background time, so a healthy session shouldn't ever need
    /// restarting. But if the process was killed (OOM, force-quit) the
    /// session ends with it; opening the app re-arms via this hook.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        if let s = session, s.state == .running || s.state == .prepared {
            return
        }
        Task { await startSession() }
    }

    private func startSession() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("KEEPALIVE_HEALTH_UNAVAILABLE")
            return
        }

        // HKWorkoutSession requires share-authorization for HKWorkoutType
        // even if we never actually save samples — the session implicitly
        // creates a workout record at end. Read-set is empty; we're not
        // collecting anything.
        do {
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: []
            )
        } catch {
            print("KEEPALIVE_AUTH_ERROR \(error.localizedDescription)")
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor

        do {
            let s = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: config
            )
            s.delegate = self
            s.startActivity(with: Date())
            session = s
            print("KEEPALIVE_START_REQUESTED workout-other")
        } catch {
            print("KEEPALIVE_START_ERROR \(error.localizedDescription)")
            session = nil
            isActive = false
        }
    }

    private func stop() {
        session?.end()
        // Session reference is cleared on the .ended state-change callback;
        // we don't nil it here to avoid racing with the delegate.
        isActive = false
        print("KEEPALIVE_STOP_REQUESTED")
    }
}

extension KeepAliveManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let toRaw = toState.rawValue
        let fromRaw = fromState.rawValue
        Task { @MainActor in
            print("KEEPALIVE_STATE from=\(fromRaw) to=\(toRaw)")
            switch toState {
            case .running:
                self.isActive = true
            case .ended, .stopped:
                self.isActive = false
                self.session = nil
                // If still enabled (e.g., session was ended by something
                // other than the user — system kill, conflicting workout)
                // and we're foreground, attempt restart.
                if self.isEnabled {
                    Task { await self.startSession() }
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let description = error.localizedDescription
        Task { @MainActor in
            print("KEEPALIVE_FAILED \(description)")
            self.isActive = false
            self.session = nil
        }
    }
}
