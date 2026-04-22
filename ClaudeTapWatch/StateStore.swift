import Foundation
import UserNotifications
import WidgetKit

/// Watch-side SwiftUI state holder for the current Claude Code status.
///
/// Source of truth, in order:
///   1. In-flight pushes processed while the app is open (willPresent,
///      didReceive, didReceiveRemoteNotification) — call `updateState`.
///   2. App Group UserDefaults, written by the Notification Service
///      Extension when pushes arrive while the app is suspended or
///      terminated. Read in `init` for first-paint and on every app
///      resume via `syncFromDeliveredNotifications`.
///   3. Delivered notifications in Notification Center — scanned as a
///      tertiary fallback.
@MainActor
final class StateStore: ObservableObject {
    static let shared = StateStore()

    @Published private(set) var currentState: TapState

    /// True while a sync is in flight AND that sync will change `currentState`.
    @Published private(set) var isSyncing: Bool = false

    private let preCommitDelay: Duration = .milliseconds(200)
    /// Canvas-based sprite render runs ~50–100K fill operations on watch
    /// hardware. 1500ms covers the worst-case paint before the spinner fades.
    private let postCommitDelay: Duration = .milliseconds(1500)

    /// Only `done` auto-expires: it's a transient completion state and we
    /// don't want "Done" sitting on the watch face forever. `needsApproval`
    /// stays until the user acts on it; `working` is always terminated by
    /// another push (done / approval). `idle` doesn't expire either.
    static let staleAfter: TimeInterval = 5 * 60

    private func shouldAutoRevert(_ state: TapState) -> Bool { state == .done }

    private var staleTimer: Timer?

    private let appGroup = ClaudeTapConstants.appGroupID
    private let stateKey = ClaudeTapConstants.Defaults.stateKey
    private let stateTimeKey = ClaudeTapConstants.Defaults.stateTimeKey

    private init() {
        let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID)
        let raw = defaults?.string(forKey: ClaudeTapConstants.Defaults.stateKey)
        let time = defaults?.double(forKey: ClaudeTapConstants.Defaults.stateTimeKey) ?? 0
        var state = raw.flatMap(TapState.init(rawValue:)) ?? .idle

        // On launch: if the cached state is `done` and its last push is
        // older than the stale threshold, go straight to idle.
        if state == .done, time > 0,
           Date().timeIntervalSince1970 - time >= Self.staleAfter {
            state = .idle
        }

        self.currentState = state
        print("STORE_INIT cached=\(raw ?? "<nil>") state=\(state.rawValue)")
        scheduleStaleRevert()
    }

    /// Re-read the cache. Returns the new state if it differs, nil otherwise.
    @discardableResult
    func reloadFromCache() -> TapState? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let raw = defaults.string(forKey: stateKey),
              let state = TapState(rawValue: raw),
              state != currentState else { return nil }
        print("CACHE_ADOPT \(state.rawValue)")
        currentState = state
        return state
    }

    /// Called on every app resume. Prefers the shared cache (written by NSE);
    /// falls back to a delivered-notifications scan. If the resulting target
    /// differs from `currentState`, shows the loading spinner for a beat
    /// while the new sprite renders underneath.
    func syncFromDeliveredNotifications() async {
        let cachedTime = UserDefaults(suiteName: appGroup)?.double(forKey: stateTimeKey) ?? 0
        let cachedState: TapState? = UserDefaults(suiteName: appGroup)?
            .string(forKey: stateKey)
            .flatMap(TapState.init(rawValue:))

        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let latestNotif = notifications.compactMap { note -> (Date, TapState)? in
            guard let raw = note.request.content.userInfo["status"] as? String,
                  let state = TapState(rawValue: raw) else { return nil }
            return (note.date, state)
        }.max(by: { $0.0 < $1.0 })

        // Prefer whichever signal is fresher between the cached write and the
        // most recent delivered notification.
        var targetState: TapState
        var targetDate: Date?
        if let (date, state) = latestNotif, date.timeIntervalSince1970 > cachedTime {
            targetState = state
            targetDate = date
        } else if let cached = cachedState {
            targetState = cached
            targetDate = nil
        } else {
            targetState = currentState
            targetDate = nil
        }

        // Stale check: `done` expires to idle; other states don't.
        let targetTimestamp = targetDate?.timeIntervalSince1970 ?? cachedTime
        if targetState == .done, targetTimestamp > 0,
           Date().timeIntervalSince1970 - targetTimestamp >= Self.staleAfter {
            targetState = .idle
            targetDate = Date()
        }

        print("SYNC target=\(targetState.rawValue) current=\(currentState.rawValue)")

        guard targetState != currentState else { return }

        isSyncing = true
        try? await Task.sleep(for: preCommitDelay)
        if let targetDate {
            persist(targetState, at: targetDate)
        } else {
            currentState = targetState
            ClaudeTapConstants.reloadComplicationIfChanged(targetState.rawValue)
        }
        try? await Task.sleep(for: postCommitDelay)
        isSyncing = false
    }

    /// Apply a state received in-flight (foreground delegate or background handler).
    func updateState(_ state: TapState) {
        if isSyncing { isSyncing = false }
        persist(state, at: Date())
    }

    private func persist(_ state: TapState, at date: Date) {
        print("PERSIST \(state.rawValue)@\(date.timeIntervalSince1970)")
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(state.rawValue, forKey: stateKey)
            defaults.set(date.timeIntervalSince1970, forKey: stateTimeKey)
        }
        currentState = state
        ClaudeTapConstants.reloadComplicationIfChanged(state.rawValue)
        scheduleStaleRevert()
    }

    /// Schedule a local timer that reverts to idle once the current state
    /// passes the stale threshold. Cancels any previously-scheduled revert.
    /// Only runs while the app process is alive — the cold-open staleness
    /// check in `init` and the complication's future timeline entries cover
    /// the cases where the app is suspended when the threshold passes.
    private func scheduleStaleRevert() {
        staleTimer?.invalidate()
        staleTimer = nil

        guard shouldAutoRevert(currentState) else { return }

        let time = UserDefaults(suiteName: appGroup)?.double(forKey: stateTimeKey) ?? 0
        let elapsed = Date().timeIntervalSince1970 - time
        let remaining = Self.staleAfter - elapsed

        if remaining <= 0 {
            persist(.idle, at: Date())
            return
        }

        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.shouldAutoRevert(self.currentState) else { return }
                self.persist(.idle, at: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }
}
