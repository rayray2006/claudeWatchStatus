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

    private init() {
        let already = UserDefaults.standard.bool(forKey: Self.pairedDefaultsKey)
        self.stage = already ? .paired : .idle
    }

    /// Called from the APNs registration callback.
    func setAPNsToken(_ token: String) {
        apnsToken = token
        if case .paired = stage { return }
        Task { await beginPairing() }
    }

    /// Reset pairing (mostly for dev / debug).
    func reset() {
        pollTask?.cancel()
        pollTask = nil
        UserDefaults.standard.set(false, forKey: Self.pairedDefaultsKey)
        stage = .idle
        if apnsToken != nil {
            Task { await beginPairing() }
        }
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
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                guard let self else { break }
                await self.checkStatus(code: code)
                if case .paired = await self.stage { break }
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
                try? await Task.sleep(for: .milliseconds(1200))
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
