import CoreLocation
import Foundation

protocol StationRepository: Sendable {
    func nearbyStations(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Station]
    func station(id: String) async throws -> Station?

    /// Stations owned by the given partner uid. Drives the Partner-side
    /// MyStations / Earnings / Dashboard screens. Returns an empty
    /// array — never nil — when the partner has no stations claimed
    /// yet, so callers can render an empty state without unwrapping.
    func partnerStations(ownerId: String) async throws -> [Station]
}
