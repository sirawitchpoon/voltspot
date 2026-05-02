import CoreLocation
import Foundation

protocol StationRepository: Sendable {
    func nearbyStations(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Station]
    func station(id: String) async throws -> Station?
}
