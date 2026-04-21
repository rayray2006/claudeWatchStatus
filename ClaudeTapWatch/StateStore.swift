import Foundation
import UserNotifications
import WidgetKit

/// Watch-side SwiftUI state holder for the current Claude Code status.
///
/// Source of truth, in order:
///   1. In-flight pushes processed while the app is open (willPresent,
///      didReceive, didReceiveRemoteNotification) — call `updateState`.
///   2. The shared file written by the Notification Service Extension when
///      pushes arrive while the app is suspended or terminated. Read
///      synchronously in `init` and whenever the scene becomes active.
///   3. Delivered notifications in Notification Center — scanned on launch
///      as a tertiary fallback.
///
/// Why a file and not UserDefaults: watchOS doesn't coherently propagate
/// UserDefaults writes across processes. The NSE writes fine, but the main
/// app can keep reading a stale cached value. File I/O always hits disk
/// and so is reliably cross-process.
@MainActor
final class StateStore: ObservableObject {
    static let shared = StateStore()

    @Published private(set) var currentState: TapState

    /// True while a sync is in flight AND that sync will change `currentState`.
    @Published private(set) var isSyncing: Bool = false

    private let preCommitDelay: Duration = .milliseconds(200)
    private let postCommitDelay: Duration = .milliseconds(700)

    private init() {
        let entry = SharedState.load()
        self.currentState = entry?.state ?? .idle
        print("STORE_INIT state=\(entry?.state.rawValue ?? "<nil>")")
    }

    /// Re-read the file store. The NSE may have updated it while the main app
    /// was suspended. Returns the new state if it differs, nil otherwise.
    @discardableResult
    func reloadFromFile() -> TapState? {
        guard let entry = SharedState.load(), entry.state != currentState else { return nil }
        print("FILE_ADOPT \(entry.state.rawValue)")
        currentState = entry.state
        return entry.state
    }

    /// Called on every app resume. Reads the shared file first (fast, always
    /// fresh), then checks delivered notifications as a belt-and-suspenders
    /// fallback. Raises `isSyncing` for long enough for the spinner to be
    /// perceivable when the state is actually changing.
    func syncFromDeliveredNotifications() async {
        let fileEntry = SharedState.load()

        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let latestNotif = notifications.compactMap { note -> (Date, TapState)? in
            guard let raw = note.request.content.userInfo["status"] as? String,
                  let state = TapState(rawValue: raw) else { return nil }
            return (note.date, state)
        }.max(by: { $0.0 < $1.0 })

        // Prefer the newer of (file entry, latest delivered notification).
        // Fall back to whichever we have.
        let target: (state: TapState, date: Date)?
        if let fileEntry, let latestNotif {
            if latestNotif.0.timeIntervalSince1970 > fileEntry.date.timeIntervalSince1970 {
                target = (latestNotif.1, latestNotif.0)
            } else {
                target = (fileEntry.state, fileEntry.date)
            }
        } else if let fileEntry {
            target = (fileEntry.state, fileEntry.date)
        } else if let latestNotif {
            target = (latestNotif.1, latestNotif.0)
        } else {
            target = nil
        }

        print("SYNC target=\(target?.state.rawValue ?? "<nil>") current=\(currentState.rawValue)")

        guard let target, target.state != currentState else { return }

        isSyncing = true
        try? await Task.sleep(for: preCommitDelay)
        persist(target.state, at: target.date)
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
        SharedState.save(state, at: date)
        currentState = state
        WidgetCenter.shared.reloadAllTimelines()
    }
}
