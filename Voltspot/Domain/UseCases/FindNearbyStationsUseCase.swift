import CoreLocation
import Foundation

struct FindNearbyStationsUseCase: Sendable {
    let stationRepository: any StationRepository

    func callAsFunction(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Station] {
        try await stationRepository.nearbyStations(near: coordinate, radiusKm: radiusKm)
    }
}
