import CoreLocation
import Foundation

struct Station: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let connectors: [Connector]
    let tariff: Tariff
    let supportsDrones: Bool
    /// Firebase uid of the partner that owns this station, or
    /// `"system-seed"` for platform-managed sample data. Optional
    /// because legacy docs predate the field — Real repos default
    /// to nil rather than failing decode.
    let partnerId: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: Station, rhs: Station) -> Bool {
        lhs.id == rhs.id
    }
}
