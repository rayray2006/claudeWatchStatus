import Foundation

/// Shared configuration for the Nudge backend, used by both iOS and Watch.
enum BackendConfig {
    static let baseURL = URL(string: "https://nudge-backend-psi.vercel.app")!

    /// Keychain key (service: com.fm.claudetap) under which the backend
    /// session token is stored on both iOS and Watch.
    static let sessionKeychainKey = "nudge.session_token"

    /// APNs environment the backend should route pushes through for this
    /// build. Free/dev provisioning delivers to sandbox; release builds
    /// (with prod provisioning) should use production.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
