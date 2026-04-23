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

    /// Standard remote-notification path — fires for the silent
    /// thinking/working/idle pushes (NSE updates cache; this is the in-app
    /// echo for state propagation when the app happens to be alive).
    /// done/approval are routed via the complication push channel instead,
    /// so this handler doesn't need to fire haptics for them.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        let raw = userInfo["status"] as? String
        print("DID_RECEIVE_REMOTE status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            StateStore.shared.updateState(state)
        }
        return .newData
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
        print("WILL_PRESENT status=\(raw ?? "<none>")")
        if let raw, let state = TapState(rawValue: raw) {
            MainActor.assumeIsolated { StateStore.shared.updateState(state) }
        }
        completionHandler([.banner, .sound, .list])
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
        print("COMPLICATION_PUSH status=\(raw ?? "<none>")")

        guard let raw, let state = TapState(rawValue: raw) else {
            completion()
            return
        }

        // Update shared state cache — same path the NSE writes to.
        if let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) {
            let cached = defaults.string(forKey: ClaudeTapConstants.Defaults.stateKey)
            defaults.set(raw, forKey: ClaudeTapConstants.Defaults.stateKey)
            if cached != raw {
                defaults.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.stateTimeKey)
            }
            defaults.synchronize()
        }

        // Tell the in-memory store too (so the StatusView shows the new state
        // immediately on next render).
        Task { @MainActor in
            StateStore.shared.updateState(state)
            // Play the user's chosen haptic — this is the whole point of the
            // complication wake channel.
            await HapticPrefs.shared.choice(for: state).play()
            completion()
        }
    }
}
