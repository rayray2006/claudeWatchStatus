import Foundation
import Observation

/// Watch-side pairing state machine.
///
/// Lifecycle:
///   1. First launch — APNs token arrives → POST /v1/pair → display a
///      6-character code.
///   2. User opens nudge-backend-psi.vercel.app/p and enters the code → the
///      backend claims it and creates an API key bound to this device.
///   3. We poll GET /v1/pair/:code every few seconds; when the backend
///      flips `claimed: true` we persist a one-time flag in UserDefaults
///      so we never show this screen again.
@MainActor
@Observable
final class Pairing {
    static let shared = Pairing()

    enum Stage {
        case idle
        case requesting
        case awaitingUser(code: String, expiresAt: Date)
        /// Brief (~1.2s) success state shown before we transition to the
        /// main StatusView — avoids a jarring flip the instant the backend
        /// confirms the pair.
        case pairedCelebrate
        case paired
        case failed(String)
    }

    private(set) var stage: Stage

    private var apnsToken: String?
    private var pollTask: Task<Void, Never>?

    private static let pairedDefaultsKey = "cued.paired"
    private static let pendingComplicationTokenKey = "cued.pendingComplicationToken"
    private static let uploadedComplicationTokenKey = "cued.uploadedComplicationToken"

    private init() {
        let already = UserDefaults.standard.bool(forKey: Self.pairedDefaultsKey)
        self.stage = already ? .paired : .idle
        // Fresh install (or post-reset) — clear any App Group state left over
        // from a previous install so the watch UI / Smart Stack widget start
        // at idle instead of resurrecting an old "done" or "approval".
        if !already {
            Self.clearSharedState()
        }
    }

    /// Called from the APNs registration callback.
    func setAPNsToken(_ token: String) {
        apnsToken = token
        // If a complication token came in before the APNs token, upload now.
        if let pending = UserDefaults.standard.string(forKey: Self.pendingComplicationTokenKey) {
            Task { await self.setComplicationToken(pending) }
        }
        if case .paired = stage { return }
        Task { await beginPairing() }
    }

    /// Called when PushKit hands us the complication-channel token. Uploads
    /// it to the backend so it can route done/approval pushes through the
    /// privileged complication wake channel. Authenticated by APNs token
    /// (which the device has natively, no API key handoff needed).
    func setComplicationToken(_ token: String) async {
        guard let apnsToken else {
            // APNs token not yet known — defer the upload until it is.
            UserDefaults.standard.set(token, forKey: Self.pendingComplicationTokenKey)
            return
        }
        let last = UserDefaults.standard.string(forKey: Self.uploadedComplicationTokenKey)
        if last == token { return }

        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("/api/v1/device/complication-token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "apnsToken": apnsToken,
            "complicationToken": token,
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                UserDefaults.standard.set(token, forKey: Self.uploadedComplicationTokenKey)
                UserDefaults.standard.removeObject(forKey: Self.pendingComplicationTokenKey)
                print("COMPLICATION_TOKEN_UPLOADED")
            } else {
                print("COMPLICATION_TOKEN_UPLOAD_FAIL status=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("COMPLICATION_TOKEN_UPLOAD_ERROR \(error.localizedDescription)")
        }
    }

    /// Reset pairing (mostly for dev / debug).
    func reset() {
        pollTask?.cancel()
        pollTask = nil
        UserDefaults.standard.set(false, forKey: Self.pairedDefaultsKey)
        Self.clearSharedState()
        stage = .idle
        if apnsToken != nil {
            Task { await beginPairing() }
        }
    }

    /// Wipe the App Group state so the watch UI and Smart Stack widget
    /// start fresh at idle. Called on first launch and on re-pair.
    private static func clearSharedState() {
        guard let defaults = UserDefaults(suiteName: ClaudeTapConstants.appGroupID) else { return }
        defaults.removeObject(forKey: ClaudeTapConstants.Defaults.stateKey)
        defaults.removeObject(forKey: ClaudeTapConstants.Defaults.stateTimeKey)
        defaults.synchronize()
    }

    /// Retry from a failed state without waiting for a new APNs token.
    func retry() {
        if case .paired = stage { return }
        Task { await beginPairing() }
    }

    private func beginPairing() async {
        guard let apnsToken else { return }
        stage = .requesting

        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("/api/v1/pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: String] = [
            "apnsToken": apnsToken,
            "bundleId": BackendConfig.watchBundleId,
            "environment": BackendConfig.apnsEnvironment,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                stage = .failed("Server error (\(status)).")
                return
            }
            let decoded = try JSONDecoder.iso.decode(PairResponse.self, from: data)
            stage = .awaitingUser(code: decoded.code, expiresAt: decoded.expiresAt)
            startPolling(code: decoded.code)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func startPolling(code: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // Fire the first check immediately (no initial sleep), then
            // tight-poll at 800ms so the user sees "Paired!" within about a
            // second of typing the code on the web form.
            while !Task.isCancelled {
                guard let self else { break }
                await self.checkStatus(code: code)
                if case .paired = await self.stage { break }
                if case .pairedCelebrate = await self.stage { break }
                try? await Task.sleep(for: .milliseconds(800))
                if Task.isCancelled { break }
            }
        }
    }

    private func checkStatus(code: String) async {
        let url = BackendConfig.baseURL.appendingPathComponent("/api/v1/pair/\(code)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                stage = .failed("Code expired. Tap to retry.")
                return
            }
            guard status == 200 else { return }
            let decoded = try JSONDecoder().decode(PairStatus.self, from: data)
            if decoded.claimed {
                UserDefaults.standard.set(true, forKey: Self.pairedDefaultsKey)
                pollTask?.cancel()
                pollTask = nil
                // Brief celebration, then flip to the main UI.
                stage = .pairedCelebrate
                try? await Task.sleep(for: .milliseconds(900))
                stage = .paired
            }
        } catch {
            // transient — keep polling
        }
    }
}

private struct PairResponse: Decodable {
    let code: String
    let expiresAt: Date
}

private struct PairStatus: Decodable {
    let claimed: Bool
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
