import UserNotifications
import WidgetKit

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended
/// or terminated.
///
/// Responsibilities:
///   1. Write the new state to the shared file in the App Group container.
///      Files are cross-process-coherent; UserDefaults is not on watchOS.
///   2. Shape the notification for display:
///      - done/approval → keep content, attach the matching Claude sprite
///      - idle/working  → clear content, set .passive, no haptic or banner
///   3. Reload the complication timeline.
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

        // 1. Persist to the shared file (unconditionally for any valid state).
        if let raw, let state = TapState(rawValue: raw) {
            SharedState.save(state)
            print("NSE_SAVED_FILE \(raw)")
            WidgetCenter.shared.reloadAllTimelines()
        }

        // 2. Shape the notification.
        if let raw, let content = bestAttemptContent {
            if Self.attentionStates.contains(raw) {
                if let url = Bundle.main.url(forResource: raw, withExtension: "png"),
                   let attachment = try? UNNotificationAttachment(identifier: raw, url: url, options: nil) {
                    content.attachments = [attachment]
                }
            } else {
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
