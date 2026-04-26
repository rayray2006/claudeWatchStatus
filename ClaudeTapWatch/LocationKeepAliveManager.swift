import Foundation
import CoreLocation

/// Alternate keep-alive mechanism using `CLLocationManager` background
/// updates. Independent of `KeepAliveManager` (which uses
/// `WKExtendedRuntimeSession`) — runs from a separate OS budget bucket, so
/// the two can stack.
///
/// How it works: with `allowsBackgroundLocationUpdates = true` and the
/// `location` background mode declared in Info.plist, the system keeps the
/// app process resident as long as it's actively updating location. We use
/// the lowest-accuracy / largest-distance-filter combination since we don't
/// actually care about location data — the side effect of updating is
/// what keeps the app alive.
///
/// Apple DTS confirms: "When in Use" authorization is sufficient for
/// background updates as long as `allowsBackgroundLocationUpdates = true`,
/// the background mode is declared, and `startUpdatingLocation` is called
/// from foreground.
///
/// Decay characteristic similar to extended-runtime sessions (~40 min to
/// 2h before the OS may stop us). Stacks with the workout-style chain.
@MainActor
final class LocationKeepAliveManager: NSObject, ObservableObject {
    static let shared = LocationKeepAliveManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var authStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()

    private static let preferenceKey = "cued.locationKeepAliveEnabled"

    private override init() {
        super.init()
        locationManager.delegate = self
        // Lowest-accuracy + huge distance filter = we don't actually want
        // location samples, just the side effect of "I am updating."
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 5000
        authStatus = locationManager.authorizationStatus
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferenceKey)
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    /// Call from `applicationDidBecomeActive`. CoreLocation requires us to
    /// kick off updates from foreground; this is the safe re-arm hook if
    /// the system stopped our updates while we were backgrounded.
    func resumeIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    private func start() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            print("LOCATION_AUTH_REQUEST")
            LocationEventLog.record(.startRequested, detail: "requesting auth")
            locationManager.requestWhenInUseAuthorization()
            // The actual start() happens in didChangeAuthorization once
            // the user grants.
        case .denied, .restricted:
            print("LOCATION_AUTH_DENIED")
            LocationEventLog.record(.startFailed, detail: "auth denied/restricted")
            isActive = false
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
            isActive = true
            print("LOCATION_KEEPALIVE_STARTED")
            LocationEventLog.record(.started, detail: "auth=\(authStatusName(status))")
        @unknown default:
            LocationEventLog.record(.startFailed, detail: "unknown auth status")
        }
    }

    private func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        isActive = false
        print("LOCATION_KEEPALIVE_STOPPED")
        LocationEventLog.record(.stopped)
    }
}

private func authStatusName(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:       return "notDetermined"
    case .denied:              return "denied"
    case .restricted:          return "restricted"
    case .authorizedWhenInUse: return "whenInUse"
    case .authorizedAlways:    return "always"
    @unknown default:          return "unknown(\(status.rawValue))"
    }
}

extension LocationKeepAliveManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let statusName = authStatusName(status)
        Task { @MainActor in
            self.authStatus = status
            print("LOCATION_AUTH_CHANGED \(statusName)")
            LocationEventLog.record(.authChanged, detail: statusName)

            // If we're enabled and just got authorized, start updating.
            if self.isEnabled,
               status == .authorizedWhenInUse || status == .authorizedAlways,
               !self.isActive {
                self.start()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // We don't use the location data — the side effect of updating
        // is keeping the app process alive. Don't log every fix; would
        // flood the log.
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let description = error.localizedDescription
        Task { @MainActor in
            print("LOCATION_KEEPALIVE_FAILED \(description)")
            LocationEventLog.record(.failed, detail: description)
        }
    }
}
