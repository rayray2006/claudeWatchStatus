import UserNotifications
import WidgetKit

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended or
/// terminated.
///
/// Responsibilities:
///   1. Write the new state to the shared App Group UserDefaults BEFORE the
///      notification is displayed. Guarantees the watch app / complication
///      reflect the latest push on next render.
///   2. Shape the notification:
///      - done/approval: keep the alert content, attach the Claude sprite.
///      - idle/working : strip the alert content and mark passive — the
///        notification is delivered silently for cache-update purposes only.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    /// States that deserve user attention (haptic + visible content).
    private static let attentionStates: Set<String> = ["done", "approval"]

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        let raw = request.content.userInfo["status"] as? String
        print("NSE_FIRED status=\(raw ?? "<none>")")

        // 1. Cache update (always, regardless of state).
        if let raw, let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
            defaults.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            WidgetCenter.shared.reloadAllTimelines()
        }

        // 2. Shape the notification.
        if let raw, let content = bestAttemptContent {
            if Self.attentionStates.contains(raw) {
                // Full notification: keep alert content, attach the sprite.
                if let url = Bundle.main.url(forResource: raw, withExtension: "png"),
                   let attachment = try? UNNotificationAttachment(identifier: raw, url: url, options: nil) {
                    content.attachments = [attachment]
                }
            } else {
                // Silent state: deliver, but make the notification invisible.
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
