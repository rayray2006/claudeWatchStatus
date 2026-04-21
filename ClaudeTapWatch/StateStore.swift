import Foundation
import UserNotifications
import WidgetKit

/// Watch-side SwiftUI state holder for the current Claude Code status.
///
/// Source of truth, in order:
///   1. In-flight pushes (foreground `willPresent`, tapped `didReceive`,
///      background `didReceiveRemoteNotification`) — call `updateState`.
///   2. Delivered notifications still in Notification Center — scanned on
///      launch / foreground via `syncFromDeliveredNotifications`.
///   3. Cached value in shared App Group UserDefaults — read synchronously
///      in `init` so the first SwiftUI render paints the right state.
///
/// Rationale: watchOS can suspend the app process, so the background push
/// handler is unreliable. Notifications, however, are delivered by the system
/// regardless of app state — so scanning them guarantees the app reflects the
/// most recent push on every launch, even if nothing in our process ran while
/// it was suspended.
@MainActor
final class StateStore: ObservableObject {
    static let shared = StateStore()

    @Published private(set) var currentState: TapState

    /// True while a sync is in flight AND that sync will change `currentState`.
    /// The UI uses this to show a loading indicator *only* when the displayed
    /// state is stale and is about to be corrected.
    @Published private(set) var isSyncing: Bool = false

    /// Time the spinner stays up BEFORE the new state is committed.
    private let preCommitSpinnerDuration: Duration = .milliseconds(300)
    /// Time the spinner stays up AFTER the new state is committed, to give the
    /// sprite view time to actually render before the spinner vanishes. Without
    /// this the spinner fades out into a brief black gap while Canvas redraws.
    private let postCommitSpinnerDuration: Duration = .milliseconds(350)

    private let appGroup = ClaudeTapConstants.appGroupID
    private let stateKey = ClaudeTapConstants.Defaults.stateKey
    private let stateTimeKey = ClaudeTapConstants.Defaults.stateTimeKey

    private init() {
        // Synchronous cache read — first render paints the cached state.
        let raw = UserDefaults(suiteName: ClaudeTapConstants.appGroupID)?
            .string(forKey: ClaudeTapConstants.Defaults.stateKey)
        let state = raw.flatMap(TapState.init(rawValue:)) ?? .idle
        self.currentState = state
        print("STORE_INIT cached=\(raw ?? "<nil>") state=\(state.rawValue)")
    }

    /// Bring the in-memory state in line with whatever the cache currently holds.
    /// Returns the adopted state if it changed, or nil if nothing changed.
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

    /// Call on every app resume. Determines the best available "target" state
    /// from the cache and delivered notifications. If that target differs from
    /// what the UI currently shows, raises `isSyncing` for a short minimum
    /// duration before committing the new state — giving the loading spinner
    /// time to render.
    func syncFromDeliveredNotifications() async {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let cachedTime = UserDefaults(suiteName: appGroup)?.double(forKey: stateTimeKey) ?? 0
        let cachedState: TapState? = UserDefaults(suiteName: appGroup)?
            .string(forKey: stateKey)
            .flatMap(TapState.init(rawValue:))

        let latestNotif = notifications.compactMap { note -> (Date, TapState)? in
            guard let raw = note.request.content.userInfo["status"] as? String,
                  let state = TapState(rawValue: raw) else { return nil }
            return (note.date, state)
        }.max(by: { $0.0 < $1.0 })

        // Pick the freshest signal: newest delivered notification if it beats
        // the cached timestamp, otherwise whatever is cached.
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
        try? await Task.sleep(for: preCommitSpinnerDuration)
        if let targetDate {
            persist(targetState, at: targetDate)
        } else {
            currentState = targetState
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Keep the spinner up for a bit longer so the sprite has time to
        // actually render before the spinner fades out.
        try? await Task.sleep(for: postCommitSpinnerDuration)
        isSyncing = false
    }

    /// Apply a state received in-flight (foreground delegate or background handler).
    func updateState(_ state: TapState) {
        // If a push arrived while the app is already open, we never needed a
        // spinner in the first place; clear it if one was up.
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
