import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

@main
struct ClaudeTapWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate
    @State private var pairing = Pairing.shared

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch pairing.stage {
        case .paired:
            StatusView()
        default:
            PairingView(pairing: pairing)
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
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func applicationWillEnterForeground() {
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func applicationDidBecomeActive() {
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

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        let raw = userInfo["status"] as? String
        if let raw, let state = TapState(rawValue: raw) {
            StateStore.shared.updateState(state)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let raw = notification.request.content.userInfo["status"] as? String
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["status"] as? String
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler()
    }
}
