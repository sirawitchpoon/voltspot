import CoreLocation
import MapKit

/// Default map region centered on Bangkok with a span wide enough to cover
/// most of Thailand. Pulls coordinates from `AppConfig` so the brand swap
/// path is consistent with currency and language.
enum ThailandRegion {
    static let center = CLLocationCoordinate2D(
        latitude: AppConfig.defaultMapCenterLat,
        longitude: AppConfig.defaultMapCenterLon
    )

    static let span = MKCoordinateSpan(
        latitudeDelta: AppConfig.defaultMapSpanDegrees,
        longitudeDelta: AppConfig.defaultMapSpanDegrees
    )

    static let region = MKCoordinateRegion(center: center, span: span)
}
