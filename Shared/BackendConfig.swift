import Foundation

/// Shared configuration for the Nudge backend.
enum BackendConfig {
    /// Short, typable alias for pairing URLs shown on the watch.
    static let shortHost = "ntap.vercel.app"
    static let baseURL = URL(string: "https://\(shortHost)")!

    /// APNs environment for pushes this device will receive. Dev builds
    /// register with Apple's sandbox; release builds (not yet provisioned)
    /// will need "production".
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static let watchBundleId = "com.fm.claudetap.watchapp"
}
