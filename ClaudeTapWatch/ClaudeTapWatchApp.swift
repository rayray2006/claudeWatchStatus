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
        return .newData
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // We no longer schedule background refreshes for push reloads (the
        // NSE handles that). Any backgroundTasks we receive here are system-
        // initiated; just mark them done.
        for task in backgroundTasks {
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
        // Only fires when the app is in the foreground. We update the state
        // in-memory here; the banner/haptic is redundant since the user is
        // already looking at the app — suppress it by passing no options.
        let raw = notification.request.content.userInfo["status"] as? String
        print("WILL_PRESENT status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
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
