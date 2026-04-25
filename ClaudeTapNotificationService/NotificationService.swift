import UserNotifications
import WidgetKit

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
        // Backend writes `ts` as JS milliseconds. Convert to Unix seconds.
        let pushTsMs = request.content.userInfo["ts"] as? Double ?? 0
        let pushTs = pushTsMs / 1000.0
        print("NSE_FIRED status=\(raw ?? "<none>") pushTs=\(pushTs)")

        if let raw, let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            let cached = defaults.string(forKey: ClaudeTapConstants.Defaults.stateKey)
            let cachedTs = defaults.double(forKey: ClaudeTapConstants.Defaults.stateTimeKey)

            // Stale-push guard: APNs can deliver out of order. If this push's
            // generation timestamp is older than what we already have cached,
            // drop the cache update entirely so a late `thinking` doesn't
            // overwrite a freshly-arrived `done`. We still call
            // `contentHandler` below so the (stripped/silent) notification
            // delivers to NC for sync's tertiary fallback.
            if pushTs > 0 && pushTs < cachedTs {
                print("NSE_SKIP_STALE pushTs=\(pushTs) < cachedTs=\(cachedTs)")
            } else {
                defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
                // Only advance the stored timestamp when the state actually
                // transitions — duplicate pushes of the same state (e.g.
                // PreToolUse firing repeatedly) must NOT reset the duration
                // timer the app shows.
                if cached != raw {
                    // Use the push's own timestamp rather than `now` so the
                    // state's "started at" reflects when the transition was
                    // actually generated, not when NSE happened to fire.
                    let stateTime = pushTs > 0 ? pushTs : Date().timeIntervalSince1970
                    defaults.set(stateTime, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
                    defaults.synchronize()
                    WidgetCenter.shared.reloadTimelines(ofKind: ClaudeTapConstants.ComplicationKind.smartStack)
                    print("NSE_RELOAD \(raw) (was \(cached ?? "nil"))")
                } else {
                    print("NSE_SKIP \(raw) (unchanged)")
                }
            }
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
