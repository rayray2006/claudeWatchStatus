import Foundation
import UserNotifications
import WatchKit

final class NotificationHandler: NSObject, ObservableObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationHandler()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                self.registerCategory()
            }
        }
    }

    private func registerCategory() {
        let category = UNNotificationCategory(
            identifier: "CLAUDE_TAP",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func triggerHaptic(for state: TapState) {
        // Play haptic on the watch
        let hapticType: WKHapticType = state == .needsApproval ? .notification : .success
        WKInterfaceDevice.current().play(hapticType)

        // Also post a minimal local notification as backup
        // This ensures haptic even if watch app is in background
        let content = UNMutableNotificationContent()
        content.title = "Claude"
        content.body = state == .needsApproval ? "Needs your approval" : "Finished working"
        content.categoryIdentifier = "CLAUDE_TAP"
        content.sound = nil // Silent — haptic only

        let request = UNNotificationRequest(
            identifier: "claude-tap-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // Suppress notification display when app is in foreground (haptic already played)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([]) // Show nothing — haptic was already triggered
    }
}
