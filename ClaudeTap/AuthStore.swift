import Foundation
import AuthenticationServices

/// Holds the user's session token and exposes sign-in / sign-out actions.
@MainActor
@Observable
final class AuthStore: NSObject {
    static let sessionKey = BackendConfig.sessionKeychainKey

    private(set) var sessionToken: String?
    private(set) var inProgress: Bool = false
    var lastError: String?

    let api = APIClient()

    override init() {
        super.init()
        self.sessionToken = Keychain.read(Self.sessionKey)
        WatchConnector.shared.shareSession(self.sessionToken)
    }

    var isSignedIn: Bool { sessionToken != nil }

    /// Exchange the identity token from a completed SIWA request for a
    /// backend session token and persist it.
    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            lastError = "No identity token from Apple"
            return
        }
        inProgress = true
        defer { inProgress = false }
        do {
            let session = try await api.signInWithApple(identityToken: idToken)
            Keychain.save(session, forKey: Self.sessionKey)
            sessionToken = session
            WatchConnector.shared.shareSession(session)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        Keychain.delete(Self.sessionKey)
        sessionToken = nil
        WatchConnector.shared.shareSession(nil)
    }

    /// Hard delete the account on the backend, then clear local state.
    func deleteAccount() async {
        guard let token = sessionToken else { return }
        inProgress = true
        defer { inProgress = false }
        do {
            try await api.deleteAccount(sessionToken: token)
            signOut()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
