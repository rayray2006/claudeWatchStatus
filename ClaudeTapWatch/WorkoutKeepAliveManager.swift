import Foundation
import HealthKit
import WatchKit

/// Keep-alive using `HKWorkoutSession` with `HKWorkoutActivityType.other`.
/// The only watchOS API that grants reliable indefinite background runtime
/// to a non-fitness app — chained `WKExtendedRuntimeSession` was tried
/// previously and degraded after a few hours via `.suppressedBySystem`.
///
/// Costs (acknowledged in Settings footer):
///   - Watch face shows green workout indicator while active.
///   - Wrist-raise auto-launches Cued instead of returning to clock.
///   - Always-On display shows our app dimmed instead of the watch face.
///   - HealthKit authorization required.
///   - Higher battery (workout subsystem keeps HR sensor warm at ~1Hz).
///
/// Off by default; user opts in via Settings.
@MainActor
final class WorkoutKeepAliveManager: NSObject, ObservableObject {
    static let shared = WorkoutKeepAliveManager()

    @Published private(set) var isActive: Bool = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    private static let preferenceKey = "cued.workoutKeepAliveEnabled"

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

    /// Call from `applicationDidBecomeActive`. Workout sessions usually
    /// survive indefinitely, so a healthy session shouldn't need restarting
    /// — but if the process was killed the session ended with it; opening
    /// the app re-arms via this hook.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        if let s = session, s.state == .running || s.state == .prepared {
            return
        }
        Task { await startSession() }
    }

    /// Call once at process startup (from `applicationDidFinishLaunching`).
    /// If the process crashed while a workout session was active, the OS
    /// keeps the session alive and gives it back here — we adopt it as our
    /// own instead of starting a new one. Apple's documented hook for this
    /// exact case; without it, we'd start a fresh session and the orphaned
    /// one would still be running invisibly until the OS reclaims it.
    func tryRecoverActiveSession() {
        guard isEnabled else { return }
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("WORKOUT_RECOVER_ERROR \(error.localizedDescription)")
                    WorkoutEventLog.record(.startFailed, detail: "recover error: \(error.localizedDescription)")
                    return
                }
                guard let recovered else {
                    print("WORKOUT_NO_SESSION_TO_RECOVER")
                    return
                }
                print("WORKOUT_RECOVERED state=\(workoutStateName(recovered.state))")
                WorkoutEventLog.record(.stateChange, detail: "recovered \(workoutStateName(recovered.state))")
                recovered.delegate = self
                self.session = recovered
                if recovered.state == .running || recovered.state == .prepared {
                    self.isActive = true
                }
            }
        }
    }

    private func startSession() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("WORKOUT_HEALTH_UNAVAILABLE")
            WorkoutEventLog.record(.startFailed, detail: "HealthKit unavailable")
            return
        }

        // HKWorkoutSession requires share-authorization for HKWorkoutType
        // even though we never save samples (the session implicitly creates
        // a workout record at end). Read-set is empty.
        do {
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: []
            )
        } catch {
            print("WORKOUT_AUTH_ERROR \(error.localizedDescription)")
            WorkoutEventLog.record(.startFailed, detail: "auth: \(error.localizedDescription)")
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
            print("WORKOUT_START_REQUESTED")
            WorkoutEventLog.record(.startRequested)
        } catch {
            print("WORKOUT_START_ERROR \(error.localizedDescription)")
            WorkoutEventLog.record(.startFailed, detail: error.localizedDescription)
            session = nil
            isActive = false
        }
    }

    private func stop() {
        session?.end()
        // Session reference is cleared on the .ended state-change callback;
        // we don't nil it here to avoid racing with the delegate.
        isActive = false
        print("WORKOUT_STOP_REQUESTED")
        WorkoutEventLog.record(.manualStop)
    }
}

private func workoutStateName(_ state: HKWorkoutSessionState) -> String {
    switch state {
    case .notStarted: return "notStarted"
    case .running:    return "running"
    case .ended:      return "ended"
    case .paused:     return "paused"
    case .prepared:   return "prepared"
    case .stopped:    return "stopped"
    @unknown default: return "unknown(\(state.rawValue))"
    }
}

extension WorkoutKeepAliveManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let toName = workoutStateName(toState)
        let fromName = workoutStateName(fromState)
        Task { @MainActor in
            print("WORKOUT_STATE \(fromName)→\(toName)")
            WorkoutEventLog.record(.stateChange, detail: "\(fromName)→\(toName)")
            switch toState {
            case .running:
                self.isActive = true
            case .ended, .stopped:
                self.isActive = false
                self.session = nil
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
            print("WORKOUT_FAILED \(description)")
            WorkoutEventLog.record(.failed, detail: description)
            self.isActive = false
            self.session = nil
        }
    }
}
