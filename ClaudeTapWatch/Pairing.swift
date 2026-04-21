import Foundation
import Observation

/// Watch-side pairing state machine.
///
/// Lifecycle:
///   1. First launch with an APNs token → POST /v1/pair, get a 6-char code,
///      show it to the user.
///   2. User enters the code on nudge.app/p in a browser → backend marks
///      it claimed.
///   3. Watch polls GET /v1/pair/:code every few seconds and flips to
///      `paired` once the backend confirms. We persist that flag in the
///      Keychain so the pair screen isn't shown again.
@MainActor
@Observable
final class Pairing {
    static let shared = Pairing()

    enum Stage {
        case idle                // no APNs token yet
        case requesting          // asking backend for a code
        case awaitingUser(code: String, expiresAt: Date)
        case paired
        case failed(String)
    }

    private(set) var stage: Stage = .idle

    private var apnsToken: String?
    private var pollTask: Task<Void, Never>?

    private static let pairedFlagKey = "nudge.paired"

    private init() {
        if Keychain.read(Self.pairedFlagKey) == "1" {
            stage = .paired
        }
    }

    /// Called from the APNs registration callback. Kicks off pairing if needed.
    func setAPNsToken(_ token: String) {
        apnsToken = token
        if case .paired = stage { return }
        Task { await beginPairing() }
    }

    func reset() {
        pollTask?.cancel()
        pollTask = nil
        Keychain.delete(Self.pairedFlagKey)
        stage = .idle
        if let apnsToken {
            Task { await beginPairing() }
        }
    }

    /// Retry from a failed state.
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
            "bundleId": "com.fm.nudge",
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
                Keychain.save("1", forKey: Self.pairedFlagKey)
                stage = .paired
                pollTask?.cancel()
                pollTask = nil
            }
        } catch {
            // Transient; keep polling.
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
