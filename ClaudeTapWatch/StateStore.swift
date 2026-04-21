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
    private let postCommitDelay: Duration = .milliseconds(700)

    private let appGroup = ClaudeTapConstants.appGroupID
    private let stateKey = ClaudeTapConstants.Defaults.stateKey
    private let stateTimeKey = ClaudeTapConstants.Defaults.stateTimeKey

    private init() {
        let raw = UserDefaults(suiteName: ClaudeTapConstants.appGroupID)?
            .string(forKey: ClaudeTapConstants.Defaults.stateKey)
        let state = raw.flatMap(TapState.init(rawValue:)) ?? .idle
        self.currentState = state
        print("STORE_INIT cached=\(raw ?? "<nil>") state=\(state.rawValue)")
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
        let targetState: TapState
        let targetDate: Date?
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

        print("SYNC target=\(targetState.rawValue) current=\(currentState.rawValue)")

        guard targetState != currentState else { return }

        isSyncing = true
        try? await Task.sleep(for: preCommitDelay)
        if let targetDate {
            persist(targetState, at: targetDate)
        } else {
            currentState = targetState
            WidgetCenter.shared.reloadAllTimelines()
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
        WidgetCenter.shared.reloadAllTimelines()
    }
}
