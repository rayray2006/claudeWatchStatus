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
    /// The NSE writes the latest push to the cache while the main app is
    /// suspended; this method lets us pick that up on resume.
    func reloadFromCache() {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let raw = defaults.string(forKey: stateKey),
              let state = TapState(rawValue: raw) else { return }
        if state != currentState {
            print("CACHE_ADOPT \(state.rawValue)")
            currentState = state
        }
    }

    /// Call on every app resume. First reloads from the shared cache (which
    /// the NSE updates in a separate process), then falls back to scanning
    /// delivered notifications for pushes the NSE might have missed.
    func syncFromDeliveredNotifications() async {
        reloadFromCache()

        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let cachedTime = UserDefaults(suiteName: appGroup)?.double(forKey: stateTimeKey) ?? 0

        let candidates = notifications.compactMap { note -> (Date, TapState)? in
            guard let raw = note.request.content.userInfo["status"] as? String,
                  let state = TapState(rawValue: raw) else { return nil }
            return (note.date, state)
        }
        print("SYNC delivered=\(notifications.count) with-status=\(candidates.count) cachedTime=\(cachedTime)")

        guard let (date, state) = candidates.max(by: { $0.0 < $1.0 }) else { return }
        print("SYNC latest=\(state.rawValue)@\(date.timeIntervalSince1970) vs cached=\(cachedTime)")
        guard date.timeIntervalSince1970 > cachedTime else { return }
        persist(state, at: date)
    }

    /// Apply a state received in-flight (foreground delegate or background handler).
    func updateState(_ state: TapState) {
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
