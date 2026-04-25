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
/// indicator, and battery drain is roughly 5-10× idle. The dominant cost is
/// the workout subsystem keeping the heart-rate sensor warm — there's no
/// API to disable that. We collect no samples (no `HKLiveWorkoutBuilder`,
/// no HR queries) — the session exists purely for its side effect of
/// keeping the app process resident so `didReceiveRemoteNotification` fires
/// for every push.
///
/// Battery-saving heuristic: auto-pause when the watch is plugged in. The
/// user typically isn't expecting wrist taps overnight while charging, and
/// charging is when the longest cumulative session-drain would otherwise
/// land. End the session when battery state flips to `.charging`/`.full`,
/// resume on `.unplugged`. Best-effort on resume — if the app process was
/// fully suspended at unplug, the observer won't fire and resume happens on
/// the next app open via `resumeIfEnabled`.
///
/// Off by default; user opts in via Settings.
@MainActor
final class KeepAliveManager: NSObject, ObservableObject {
    static let shared = KeepAliveManager()

    @Published private(set) var isActive: Bool = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var batteryObserver: NSObjectProtocol?
    private var idleTimer: Timer?

    /// End the session if there's no push or app activity for this long.
    /// Saves battery during the user's natural idle windows (away from
    /// keyboard, sleeping, between sessions). Re-arms on next app open.
    private static let idleTimeout: TimeInterval = 30 * 60

    private static let preferenceKey = "cued.keepAliveEnabled"

    private override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        batteryObserver = NotificationCenter.default.addObserver(
            forName: WKInterfaceDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                Self.shared.handleBatteryStateChange()
            }
        }
    }

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
    /// restarting. But if the process was killed (OOM, force-quit, our
    /// own auto-pause-on-charge fired earlier, or the idle timeout ended
    /// the session), opening the app re-arms via this hook.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        // Honor the on-charger auto-pause from this entry too.
        if isOnCharger {
            print("KEEPALIVE_SKIP_CHARGING")
            return
        }
        if let s = session, s.state == .running || s.state == .prepared {
            // Session already running — just bump the idle timer since the
            // user opening the app counts as activity.
            scheduleIdleTimer()
            return
        }
        Task { await startSession() }
    }

    /// Reset the 30-minute idle timer. Called from every push handler and
    /// from `applicationDidBecomeActive` so the session only ends after a
    /// genuine quiet stretch with no app activity. No-op when no session
    /// is running.
    func markActivity() {
        scheduleIdleTimer()
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard isEnabled, let s = session,
              s.state == .running || s.state == .prepared else { return }
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
        s.end()
    }

    private var isOnCharger: Bool {
        let state = WKInterfaceDevice.current().batteryState
        return state == .charging || state == .full
    }

    private func handleBatteryStateChange() {
        let state = WKInterfaceDevice.current().batteryState
        switch state {
        case .charging, .full:
            if let s = session, s.state == .running || s.state == .prepared {
                print("KEEPALIVE_AUTO_PAUSE_CHARGING")
                s.end()
            }
        case .unplugged:
            if isEnabled, session == nil {
                print("KEEPALIVE_AUTO_RESUME_UNPLUG")
                Task { await startSession() }
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func startSession() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("KEEPALIVE_HEALTH_UNAVAILABLE")
            return
        }
        // Defense-in-depth: still skip if charging at start time. The
        // toggle-on path can race the battery observer.
        if isOnCharger {
            print("KEEPALIVE_SKIP_CHARGING")
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
            // Schedule the initial idle window from session start; each
            // arriving push will reset it via markActivity().
            scheduleIdleTimer()
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
        idleTimer?.invalidate()
        idleTimer = nil
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
                self.idleTimer?.invalidate()
                self.idleTimer = nil
                // No auto-restart here. All restart paths flow through
                // resumeIfEnabled() (called from applicationDidBecomeActive)
                // or the unplug branch of handleBatteryStateChange. This
                // keeps idle-timeout / on-charger / user-toggle ends from
                // looping back into a fresh session unintentionally.
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
