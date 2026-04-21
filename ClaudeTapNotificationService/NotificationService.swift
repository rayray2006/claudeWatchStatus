import UserNotifications
import WidgetKit

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended or
/// terminated.
///
/// Why: the system doesn't reliably wake a suspended watchOS app for
/// background pushes, so the main app's cache can be stale on next open. This
/// extension writes the new state to the shared App Group UserDefaults BEFORE
/// the notification is displayed, guaranteeing that when the user opens the
/// app its synchronous cache read returns the current state with zero flash.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        if let raw = request.content.userInfo["status"] as? String,
           let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
            defaults.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            WidgetCenter.shared.reloadAllTimelines()
        }

        contentHandler(bestAttemptContent ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
