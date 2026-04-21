import Foundation

/// Watch-side glue for keeping the backend's `devices` table in sync with
/// this watch's current APNs device token.
///
/// Needs two things to register:
///   1. The user's session token (received from iPhone via WatchConnectivity)
///   2. The APNs device token (received from `didRegisterForRemoteNotifications`)
///
/// Whenever either arrives and the other is already known, POST to
/// /api/v1/devices. The backend upserts on (user_id, apns_token).
@MainActor
final class DeviceRegistrar {
    static let shared = DeviceRegistrar()

    private var sessionToken: String?
    private var apnsToken: String?
    private var lastRegisteredApns: String?

    private init() {
        sessionToken = Keychain.read(BackendConfig.sessionKeychainKey)
    }

    func setSession(_ token: String?) {
        if let token, !token.isEmpty {
            Keychain.save(token, forKey: BackendConfig.sessionKeychainKey)
            sessionToken = token
        } else {
            Keychain.delete(BackendConfig.sessionKeychainKey)
            sessionToken = nil
        }
        tryRegister()
    }

    func setAPNs(_ token: String) {
        apnsToken = token
        tryRegister()
    }

    private func tryRegister() {
        guard let apnsToken, let sessionToken else { return }
        // Skip duplicate registration for the same (session, apns) pair.
        // Backend upsert is cheap but network isn't.
        let key = sessionToken + ":" + apnsToken
        if lastRegisteredApns == key { return }
        lastRegisteredApns = key
        Task { await register(apns: apnsToken, session: sessionToken) }
    }

    private func register(apns: String, session: String) async {
        let url = BackendConfig.baseURL.appendingPathComponent("/api/v1/devices")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(session)", forHTTPHeaderField: "authorization")
        let body: [String: String] = [
            "apnsToken": apns,
            "bundleId": "com.fm.claudetap.watchapp",
            "environment": BackendConfig.apnsEnvironment,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                print("DEVICE_REGISTERED apns=\(apns.prefix(8))…")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("DEVICE_REGISTER_FAILED \(status): \(body)")
                // Don't mark as registered — retry next push/launch.
                lastRegisteredApns = nil
            }
        } catch {
            print("DEVICE_REGISTER_ERROR \(error.localizedDescription)")
            lastRegisteredApns = nil
        }
    }
}
