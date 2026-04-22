import SwiftUI
import UserNotifications
import WatchKit

@main
struct ClaudeTapWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate
    @State private var pairing = Pairing.shared

    var body: some Scene {
        WindowGroup {
            if case .paired = pairing.stage {
                StatusView()
            } else {
                PairingView(pairing: pairing)
            }
        }
    }
}

@MainActor
final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                WKExtension.shared().registerForRemoteNotifications()
            }
        }
        // Recover state from any notifications delivered while the app was suspended.
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    /// Fires before `scenePhase` propagates to SwiftUI — gives us the earliest
    /// possible hook to sync state on every app resume.
    func applicationWillEnterForeground() {
        print("WILL_ENTER_FOREGROUND")
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func applicationDidBecomeActive() {
        print("DID_BECOME_ACTIVE")
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("APNS_TOKEN: \(tokenString)")
        UserDefaults.standard.set(true, forKey: "apns_registered")
        Pairing.shared.setAPNsToken(tokenString)
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        print("APNS_REGISTER_FAILED: \(error.localizedDescription)")
    }

    /// Called when a push arrives with content-available:1 — even if app is in background.
    /// This is how we catch state changes that happen while the app is closed.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        let raw = userInfo["status"] as? String
        print("DID_RECEIVE_REMOTE status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            StateStore.shared.updateState(state)
            // Play the user's chosen haptic for this state (if any).
            Task { await HapticPrefs.shared.choice(for: state).play() }
        }
        // Heartbeat: keep the app warm enough for the next push to wake us
        // and fire its haptic. Without this the app gets deep-suspended after
        // a few minutes of inactivity and subsequent pushes silently land in
        // Notification Center without firing didReceiveRemoteNotification.
        Self.scheduleWarmKeepAlive()
        return .newData
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // The heartbeat fires here. Re-schedule one more so the warm window
        // keeps rolling, then complete. The system rate-limits us regardless,
        // so this won't pin the app awake — it just nudges priority up.
        Self.scheduleWarmKeepAlive()
        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    /// Schedules a low-priority background refresh ~60s from now. Each call
    /// queues an additional task; the system coalesces / throttles aggressive
    /// callers. Used as an OS-priority signal so the app isn't deep-suspended
    /// between pushes.
    private static func scheduleWarmKeepAlive() {
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(60),
            userInfo: nil
        ) { error in
            if let error {
                print("KEEPALIVE_SCHED_FAIL \(error.localizedDescription)")
            }
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    // Foreground: notification about to be presented.
    // UN delegate methods run on the main thread — use `assumeIsolated` so the
    // MainActor-isolated StateStore call is inline (no Task dispatch hop).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Fires when a push arrives while the app is foreground (or transiently
        // backgrounded but still alive). We update state, suppress the system's
        // banner, AND play the user's chosen haptic ourselves — without this
        // last step, foreground-arriving pushes were silent.
        let raw = notification.request.content.userInfo["status"] as? String
        print("WILL_PRESENT status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
            Task { await HapticPrefs.shared.choice(for: state).play() }
        }
        completionHandler([])
    }

    // User tapped notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["status"] as? String
        print("DID_RECEIVE status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler()
    }
}
