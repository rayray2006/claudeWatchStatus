import UserNotifications
import WidgetKit

/// Runs in a tiny separate process every time an APNs push with
/// `mutable-content: 1` arrives — even when the main watch app is suspended or
/// terminated.
///
/// Responsibilities:
///   1. Write the new state to the shared App Group UserDefaults BEFORE the
///      notification is displayed, so the watch app's synchronous cache read
///      returns the latest state with zero flash when the user opens it.
///   2. Attach the state-specific pixel-art PNG to the notification so the
///      long-look on the watch shows the matching Claude character.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        let status = request.content.userInfo["status"] as? String ?? "<none>"
        let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID)
        print("NSE_FIRED status=\(status) defaults=\(defaults != nil ? "ok" : "nil")")

        if let raw = request.content.userInfo["status"] as? String {
            if let defaults {
                defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
                defaults.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
                WidgetCenter.shared.reloadAllTimelines()
            }

            if let url = Bundle.main.url(forResource: raw, withExtension: "png") {
                do {
                    let attachment = try UNNotificationAttachment(identifier: raw, url: url, options: nil)
                    bestAttemptContent?.attachments = [attachment]
                    print("NSE_ATTACHED \(raw) from \(url.lastPathComponent)")
                } catch {
                    print("NSE_ATTACH_FAILED \(raw): \(error.localizedDescription)")
                }
            } else {
                print("NSE_NO_RESOURCE \(raw)")
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
