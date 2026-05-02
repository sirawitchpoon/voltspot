import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class StationFinderViewModel {
    var stations: [Station] = []
    var selectedStation: Station?
    var cameraPosition: MapCameraPosition

    private let findNearby: FindNearbyStationsUseCase

    init() {
        self.findNearby = FindNearbyStationsUseCase(
            stationRepository: RealStationRepository()
        )
        self.cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: AppConfig.defaultMapCenterLat,
                    longitude: AppConfig.defaultMapCenterLon
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: AppConfig.defaultMapSpanDegrees,
                    longitudeDelta: AppConfig.defaultMapSpanDegrees
                )
            )
        )
    }

    func loadStations() async {
        do {
            stations = try await findNearby(
                near: CLLocationCoordinate2D(
                    latitude: AppConfig.defaultMapCenterLat,
                    longitude: AppConfig.defaultMapCenterLon
                ),
                radiusKm: 1500
            )
        } catch {
            stations = []
        }
    }
}
