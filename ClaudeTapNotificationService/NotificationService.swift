import UserNotifications
import WidgetKit

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended
/// or terminated.
///
/// IMPORTANT: the cache write (step 1 below) happens on every invocation
/// regardless of whether the delivered notification is visible or silent.
/// Setting `interruptionLevel = .passive` and clearing title/body only
/// shapes how the notification itself displays — the side effects
/// (UserDefaults write + widget reload) have already happened.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    private static let attentionStates: Set<String> = ["done", "approval"]

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        let raw = request.content.userInfo["status"] as? String
        print("NSE_FIRED status=\(raw ?? "<none>")")

        // 1. Cache update (always).
        if let raw, let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
            defaults.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            WidgetCenter.shared.reloadAllTimelines()
            print("NSE_WROTE \(raw)")
        }

        // 2. Shape the notification for display.
        if let raw, let content = bestAttemptContent {
            if Self.attentionStates.contains(raw) {
                // Full notification + Claude sprite attachment.
                if let url = Bundle.main.url(forResource: raw, withExtension: "png"),
                   let attachment = try? UNNotificationAttachment(identifier: raw, url: url, options: nil) {
                    content.attachments = [attachment]
                }
            } else {
                // Silent: delivered, but no haptic, no banner, no content.
                content.title = ""
                content.subtitle = ""
                content.body = ""
                content.sound = nil
                content.attachments = []
                content.interruptionLevel = .passive
                content.relevanceScore = 0
            }
        }

        contentHandler(bestAttemptContent ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
