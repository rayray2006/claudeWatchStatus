import UserNotifications

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended
/// or terminated.
///
/// IMPORTANT: the cache write happens on every invocation regardless of
/// whether the delivered notification is visible or silent. Clearing the
/// title/body and marking .passive only shapes how the notification displays
/// — the side effects (UserDefaults write, widget reload) have already
/// happened by the time contentHandler is called.
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
            print("NSE_WROTE \(raw)")
        }

        // 2. Shape the notification for display.
        if let raw, !Self.attentionStates.contains(raw),
           let content = bestAttemptContent {
            // Silent: delivered, but no haptic, no banner, no content.
            content.title = ""
            content.subtitle = ""
            content.body = ""
            content.sound = nil
            content.interruptionLevel = .passive
            content.relevanceScore = 0
        }

        contentHandler(bestAttemptContent ?? request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
