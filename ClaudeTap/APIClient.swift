import Foundation

/// Typed async client for the Nudge backend.
///
/// Exchanges Sign In with Apple identity tokens for session tokens, manages
/// the user's API keys, and forwards test pushes.
actor APIClient {
    static let baseURL = URL(string: "https://nudge-backend-psi.vercel.app")!

    struct APIError: Error, LocalizedError {
        let status: Int
        let body: String
        var errorDescription: String? { "HTTP \(status): \(body)" }
    }

    // MARK: - Auth

    struct SignInResponse: Decodable { let sessionToken: String }
    func signInWithApple(identityToken: String) async throws -> String {
        let payload = ["identityToken": identityToken]
        let response: SignInResponse = try await post("/api/v1/auth/apple", payload: payload, sessionToken: nil)
        return response.sessionToken
    }

    func deleteAccount(sessionToken: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: "/api/v1/auth/account", sessionToken: sessionToken)
    }

    // MARK: - API keys

    struct APIKeySummary: Decodable, Identifiable {
        let id: String
        let prefix: String
        let label: String?
        let createdAt: Date
        let lastUsedAt: Date?
    }

    struct CreatedAPIKey: Decodable {
        let id: String
        let key: String       // plaintext — shown once
        let prefix: String
        let createdAt: Date
    }

    struct APIKeyList: Decodable { let keys: [APIKeySummary] }

    func listAPIKeys(sessionToken: String) async throws -> [APIKeySummary] {
        let response: APIKeyList = try await request("GET", path: "/api/v1/api-keys", sessionToken: sessionToken)
        return response.keys
    }

    func createAPIKey(sessionToken: String, label: String?) async throws -> CreatedAPIKey {
        let body: [String: String?] = ["label": label]
        return try await post("/api/v1/api-keys", payload: body, sessionToken: sessionToken)
    }

    func revokeAPIKey(id: String, sessionToken: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: "/api/v1/api-keys/\(id)", sessionToken: sessionToken)
    }

    // MARK: - Push (test)

    struct PushResult: Decodable {
        let delivered: Int
        let invalidated: Int
    }

    func sendPush(apiKey: String, status: String) async throws -> PushResult {
        let body = ["status": status]
        return try await post("/api/v1/push", payload: body, sessionToken: nil, overrideAuth: "Bearer \(apiKey)")
    }

    // MARK: - Devices (for iOS-side settings; Watch registers its own)

    struct DeviceSummary: Decodable, Identifiable {
        let id: String
        let bundleId: String
        let environment: String
        let updatedAt: Date
        let lastPushedAt: Date?
        let isActive: Bool
    }

    struct DeviceList: Decodable { let devices: [DeviceSummary] }

    func listDevices(sessionToken: String) async throws -> [DeviceSummary] {
        let response: DeviceList = try await request("GET", path: "/api/v1/devices", sessionToken: sessionToken)
        return response.devices
    }

    // MARK: - Internal

    private struct EmptyResponse: Decodable {}

    private func post<T: Decodable, B: Encodable>(
        _ path: String,
        payload: B,
        sessionToken: String?,
        overrideAuth: String? = nil,
    ) async throws -> T {
        let url = Self.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let overrideAuth {
            req.setValue(overrideAuth, forHTTPHeaderField: "authorization")
        } else if let sessionToken {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")
        }
        req.httpBody = try JSONEncoder().encode(payload)
        return try await send(req)
    }

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        sessionToken: String?,
    ) async throws -> T {
        let url = Self.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let sessionToken {
            req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")
        }
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(httpStatus) else {
            throw APIError(status: httpStatus, body: String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
