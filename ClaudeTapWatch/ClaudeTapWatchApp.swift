import PushKit
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

/// Per-state debounce so the same state's haptic doesn't fire twice when
/// both the regular alert path (NSE/willPresent/didReceiveRemoteNotification)
/// AND the PushKit complication wake handler land within a few seconds of
/// each other. Different states are independent — a thinking → working →
/// done sequence within 3s still fires three haptics (assuming each state's
/// HapticPrefs choice isn't .none).
@MainActor
private var lastHapticAtByState: [TapState: Date] = [:]
private let hapticDebounceWindow: TimeInterval = 3

@MainActor
func playHapticDebounced(for state: TapState) async {
    let now = Date()
    if let last = lastHapticAtByState[state], now.timeIntervalSince(last) < hapticDebounceWindow {
        print("HAPTIC_SKIP debounced \(state.rawValue)")
        PushEventLog.record(.hapticSkippedDebounce, detail: state.rawValue)
        return
    }
    lastHapticAtByState[state] = now
    let choice = HapticPrefs.shared.choice(for: state)
    if choice == .none {
        print("HAPTIC_SKIP_NONE \(state.rawValue)")
        PushEventLog.record(.hapticSkippedNone, detail: state.rawValue)
        return
    }
    print("HAPTIC_PLAY \(state.rawValue) (\(choice.rawValue))")
    PushEventLog.record(.hapticPlayed, detail: "\(state.rawValue) (\(choice.rawValue))")
    await choice.play()
}

@MainActor
final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    /// PushKit registry for the privileged complication wake channel.
    /// Receives a separate token from regular APNs registration; pushes sent
    /// with `apns-push-type: complication` to that token wake the app even
    /// from deep suspension (~50/day device-shared budget).
    private let pkRegistry = PKPushRegistry(queue: .main)
    private lazy var pkDelegate = ComplicationPushDelegate()

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

        // Register PKPushRegistry for the complication wake channel. The
        // delegate handles incoming complication pushes (state cache updates +
        // haptic) and uploads the resulting token to the backend so it can
        // route done/approval pushes through this channel.
        pkRegistry.delegate = pkDelegate
        pkRegistry.desiredPushTypes = [.complication]
    }

    /// Sync state on every app resume so the UI matches the cache.
    func applicationWillEnterForeground() {
        print("WILL_ENTER_FOREGROUND")
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
    }

    func applicationDidBecomeActive() {
        print("DID_BECOME_ACTIVE")
        Task { await StateStore.shared.syncFromDeliveredNotifications() }
        // Re-arm the workout keep-alive if user has it enabled. Workout
        // sessions must be started from foreground (Apple constraint), so
        // this lifecycle hook is the recovery point.
        WorkoutKeepAliveManager.shared.resumeIfEnabled()
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

    /// Fires when a push with `content-available: 1` arrives and the OS
    /// wakes the app (foreground or warm background). Updates state and
    /// plays the user's chosen haptic — this is the path that delivers a
    /// haptic for users in Notification Center Only mode, where the system
    /// won't fire one on its own.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        let raw = userInfo["status"] as? String
        let pushTime = Self.pushTimestamp(from: userInfo)
        print("DID_RECEIVE_REMOTE status=\(raw ?? "<none>") pushTs=\(pushTime?.timeIntervalSince1970 ?? 0)")
        PushEventLog.record(.backgroundDelivered, detail: raw ?? "<none>")
        if let raw, let state = TapState(rawValue: raw) {
            StateStore.shared.updateState(state, pushTimestamp: pushTime)
            await playHapticDebounced(for: state)
        }
        return .newData
    }

    /// Backend writes `ts` as JS milliseconds in the payload top level.
    /// Returns nil if absent — falls back to wall-clock `now` downstream.
    static func pushTimestamp(from userInfo: [AnyHashable: Any]) -> Date? {
        guard let ms = userInfo["ts"] as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let raw = userInfo["status"] as? String
        let pushTsMs = userInfo["ts"] as? Double ?? 0
        let pushTime: Date? = pushTsMs > 0 ? Date(timeIntervalSince1970: pushTsMs / 1000.0) : nil
        print("WILL_PRESENT status=\(raw ?? "<none>") pushTs=\(pushTime?.timeIntervalSince1970 ?? 0)")
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated {
                PushEventLog.record(.foregroundDelivered, detail: raw)
                StateStore.shared.updateState(state, pushTimestamp: pushTime)
            }
            // Play our chosen haptic explicitly — the system suppresses
            // notification haptics in Notification Center Only mode, so we
            // can't rely on .sound to fire one. We omit .sound below to
            // keep it single rather than doubled for users with banners.
            Task { await playHapticDebounced(for: state) }
        }
        completionHandler([.banner, .list])
    }

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

/// PushKit complication-channel delegate. Receives done/approval pushes
/// even when the app is deep-suspended.
final class ComplicationPushDelegate: NSObject, PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        guard type == .complication else { return }
        let tokenString = credentials.token.map { String(format: "%02x", $0) }.joined()
        print("COMPLICATION_TOKEN: \(tokenString)")
        Task { await Pairing.shared.setComplicationToken(tokenString) }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .complication else { return }
        print("COMPLICATION_TOKEN_INVALIDATED")
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .complication else { completion(); return }

        let raw = payload.dictionaryPayload["status"] as? String
        let pushTsMs = payload.dictionaryPayload["ts"] as? Double ?? 0
        let pushTs = pushTsMs / 1000.0
        let pushTime: Date? = pushTs > 0 ? Date(timeIntervalSince1970: pushTs) : nil
        print("COMPLICATION_PUSH status=\(raw ?? "<none>") pushTs=\(pushTs)")

        guard let raw, let state = TapState(rawValue: raw) else {
            completion()
            return
        }

        // Update shared state cache — same path the NSE writes to. Apply the
        // same stale-push guard NSE uses so out-of-order PushKit deliveries
        // don't regress the visible state.
        if let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            let cachedTs = defaults.double(forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            if pushTs > 0 && pushTs < cachedTs {
                print("COMPLICATION_PUSH_SKIP_STALE pushTs=\(pushTs) < cachedTs=\(cachedTs)")
                completion()
                return
            }
            let cached = defaults.string(forKey: ClaudeTapConstants.Defaults.stateKey)
            defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
            if cached != raw {
                let stateTime = pushTs > 0 ? pushTs : Date().timeIntervalSince1970
                defaults.set(stateTime, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            }
            defaults.synchronize()
        }

        // Tell the in-memory store too (so the StatusView shows the new state
        // immediately on next render). Ack PushKit synchronously so the system
        // can re-suspend us promptly; the haptic plays asynchronously.
        Task { @MainActor in
            PushEventLog.record(.complicationDelivered, detail: raw)
            StateStore.shared.updateState(state, pushTimestamp: pushTime)
            await playHapticDebounced(for: state)
        }
        completion()
    }
}
