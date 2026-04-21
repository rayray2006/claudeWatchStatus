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
///   3. Cached value in shared App Group UserDefaults — used for instant UI
///      on app launch before the async scan completes.
///
/// Rationale: watchOS can suspend the app process, so the background push
/// handler is unreliable. Notifications, however, are delivered by the system
/// regardless of app state — so scanning them guarantees the app reflects the
/// most recent push on every launch, even if nothing in our process ran while
/// it was suspended.
final class StateStore: ObservableObject, @unchecked Sendable {
    static let shared = StateStore()

    @Published var currentState: TapState = .idle

    private let appGroup = ClaudeTapConstants.appGroupID
    private let stateKey = ClaudeTapConstants.Defaults.stateKey
    private let stateTimeKey = ClaudeTapConstants.Defaults.stateTimeKey

    private init() {
        loadCached()
    }

    /// Scan delivered notifications and adopt the newest `status` payload if
    /// it's fresher than the cached state. Safe to call repeatedly.
    func syncFromDeliveredNotifications() async {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let cachedTime = UserDefaults(suiteName: appGroup)?.double(forKey: stateTimeKey) ?? 0

        let latest = notifications
            .compactMap { note -> (Date, TapState)? in
                guard let raw = note.request.content.userInfo["status"] as? String,
                      let state = TapState(rawValue: raw) else { return nil }
                return (note.date, state)
            }
            .max(by: { $0.0 < $1.0 })

        guard let (date, state) = latest,
              date.timeIntervalSince1970 > cachedTime else { return }
        persist(state, at: date)
    }

    /// Apply a state received in-flight (foreground delegate or background handler).
    func updateState(_ state: TapState) {
        persist(state, at: Date())
    }

    private func loadCached() {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let raw = defaults.string(forKey: stateKey),
              let state = TapState(rawValue: raw) else { return }
        DispatchQueue.main.async { self.currentState = state }
    }

    private func persist(_ state: TapState, at date: Date) {
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(state.rawValue, forKey: stateKey)
            defaults.set(date.timeIntervalSince1970, forKey: stateTimeKey)
        }
        DispatchQueue.main.async {
            self.currentState = state
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
