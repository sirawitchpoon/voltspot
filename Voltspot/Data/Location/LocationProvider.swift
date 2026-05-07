import CoreLocation
import Foundation

/// Wraps `CLLocationManager` so SwiftUI views (which can't conform to
/// the `NSObject`-based `CLLocationManagerDelegate`) can observe
/// authorization + location changes through plain Swift closures.
///
/// Why a wrapper instead of putting the delegate on
/// `StationFinderViewModel`:
/// - `CLLocationManagerDelegate` requires `NSObject` conformance,
///   which we'd rather not push onto an `@Observable` class.
/// - Lets a future view (Partner side, route planner) reuse the same
///   permission flow without re-implementing the delegate plumbing.
///
/// Privacy + UX:
/// - Uses `requestWhenInUseAuthorization` only — never `Always`. We
///   don't need background location and asking for it would tank the
///   App Store privacy nutrition label.
/// - `desiredAccuracy = kCLLocationAccuracyHundredMeters` — finding
///   "stations near me" doesn't need GPS-grade precision and the
///   coarser fix is faster + saves battery.
/// - Stops updates as soon as we have a usable fix; resumes on
///   demand (caller decides via `start`).
@MainActor
final class LocationProvider: NSObject {

    /// The latest authorization status. `notDetermined` until the
    /// system delivers the first delegate callback.
    private(set) var authorizationStatus: CLAuthorizationStatus

    /// Closure invoked on the main actor whenever authorization
    /// changes. Set once by the consumer (typically in `init` of the
    /// view model that owns this provider).
    var onAuthorizationChanged: (@MainActor (CLAuthorizationStatus) -> Void)?

    /// Closure invoked when a usable fix arrives. Coordinate is
    /// Earth-frame WGS84.
    var onLocationFix: (@MainActor (CLLocationCoordinate2D) -> Void)?

    /// Closure invoked when CoreLocation gives up on a fix attempt.
    /// Currently unused by the UI layer — caller can log or ignore.
    var onError: (@MainActor (Error) -> Void)?

    private let manager: CLLocationManager

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Don't burn battery on tiny movements. ~250m matches the
        // tightest radius the StationFinder ever queries (zoom-in
        // close mode); below that the user is almost certainly
        // standing still relative to fixed station coordinates.
        manager.distanceFilter = 250
    }

    /// Returns true once the user has either approved or denied
    /// CoreLocation. Used to decide whether to prompt or to fall
    /// back to a default map center silently.
    var isAuthorizationDecided: Bool {
        switch authorizationStatus {
        case .notDetermined: return false
        default: return true
        }
    }

    /// Returns true when we're actually allowed to read the location.
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Triggers the system permission prompt if we haven't asked
    /// before. No-op once the user has decided.
    func requestWhenInUseIfNeeded() {
        guard !isAuthorizationDecided else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Starts streaming locations. Caller is expected to have either
    /// already prompted for permission or to be operating under a
    /// `notDetermined` state (the system will prompt automatically
    /// on the first fix request — but we prefer the explicit prompt
    /// flow for clearer UX).
    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    /// Stops streaming. Battery-friendly when the StationFinder tab
    /// goes off-screen.
    func stop() {
        manager.stopUpdatingLocation()
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    // CLLocationManagerDelegate methods are called on an arbitrary
    // queue. `nonisolated` opts each method out of MainActor
    // isolation so the framework can call us; we hop to the main
    // actor inside before touching our own state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.onAuthorizationChanged?(status)
            // Auto-start updates the moment the user grants — the
            // common case where they tap "Allow" and expect the map
            // to recenter without any further ceremony.
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.startUpdatingLocation()
            case .denied, .restricted, .notDetermined:
                self.manager.stopUpdatingLocation()
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        // Reject very stale fixes that come through from the cache
        // when CoreLocation warms up.
        guard abs(last.timestamp.timeIntervalSinceNow) < 30 else { return }
        let coordinate = last.coordinate
        Task { @MainActor in
            self.onLocationFix?(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.onError?(error)
        }
    }
}
