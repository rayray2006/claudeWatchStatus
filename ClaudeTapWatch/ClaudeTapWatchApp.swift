import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

@main
struct ClaudeTapWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            StatusView()
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
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("APNS_TOKEN: \(tokenString)")
        UserDefaults.standard.set(true, forKey: "apns_registered")
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        print("APNS_REGISTER_FAILED: \(error.localizedDescription)")
    }

    /// Called when a push arrives with content-available:1 — even if app is in background.
    /// This is how we catch state changes that happen while the app is closed.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        if let status = userInfo["status"] as? String,
           let state = TapState(rawValue: status) {
            StateStore.shared.updateState(state)
            // Schedule background refresh as a backup trigger for the widget.
            WKExtension.shared().scheduleBackgroundRefresh(
                withPreferredDate: Date().addingTimeInterval(2),
                userInfo: nil
            ) { _ in }
            if state.needsTap {
                WKInterfaceDevice.current().play(state == .needsApproval ? .notification : .success)
            }
        }
        return .newData
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompletedWithSnapshot(false)
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
        if let raw = notification.request.content.userInfo["status"] as? String,
           let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler([.banner])
    }

    // User tapped notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo["status"] as? String,
           let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler()
    }
}
