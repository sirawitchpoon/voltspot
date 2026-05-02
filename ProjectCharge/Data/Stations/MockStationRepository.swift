import CoreLocation
import Foundation

/// Hardcoded sample stations across Thailand. Replace with a networked
/// implementation when a backend is wired in. Distance filter is a naive
/// great-circle approximation — fine for a 6-row mock dataset.
struct MockStationRepository: StationRepository {

    func nearbyStations(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Station] {
        Self.allSamples.filter { station in
            let dKm = haversine(
                lat1: coordinate.latitude,
                lon1: coordinate.longitude,
                lat2: station.latitude,
                lon2: station.longitude
            )
            return dKm <= radiusKm
        }
    }

    func station(id: String) async throws -> Station? {
        Self.allSamples.first { $0.id == id }
    }

    private func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static let allSamples: [Station] = [
        Station(
            id: "stn-bkk-01",
            name: "Asoke EV Hub",
            address: "Sukhumvit Rd, Khlong Toei, Bangkok",
            latitude: 13.7373,
            longitude: 100.5602,
            connectors: [
                Connector(id: "stn-bkk-01-c1", kind: .ev, standard: .ccs2, powerKW: 120, status: .available),
                Connector(id: "stn-bkk-01-c2", kind: .ev, standard: .type2, powerKW: 22, status: .available),
            ],
            tariff: Tariff(pricePerKWhSatang: 750, sessionFeeSatang: 0),
            supportsDrones: false
        ),
        Station(
            id: "stn-bkk-02",
            name: "Siam Paragon FastCharge",
            address: "Rama I Rd, Pathum Wan, Bangkok",
            latitude: 13.7466,
            longitude: 100.5347,
            connectors: [
                Connector(id: "stn-bkk-02-c1", kind: .ev, standard: .chademo, powerKW: 50, status: .occupied),
                Connector(id: "stn-bkk-02-c2", kind: .ev, standard: .ccs2, powerKW: 150, status: .available),
            ],
            tariff: Tariff(pricePerKWhSatang: 850, sessionFeeSatang: 2000),
            supportsDrones: false
        ),
        Station(
            id: "stn-cnx-01",
            name: "Nimman Charge Point",
            address: "Nimmanhaemin Rd, Chiang Mai",
            latitude: 18.7976,
            longitude: 98.9669,
            connectors: [
                Connector(id: "stn-cnx-01-c1", kind: .ev, standard: .type2, powerKW: 22, status: .available),
            ],
            tariff: Tariff(pricePerKWhSatang: 700, sessionFeeSatang: 0),
            supportsDrones: false
        ),
        Station(
            id: "stn-hkt-01",
            name: "Patong Beach EV",
            address: "Patong, Phuket",
            latitude: 7.8967,
            longitude: 98.2967,
            connectors: [
                Connector(id: "stn-hkt-01-c1", kind: .ev, standard: .ccs2, powerKW: 100, status: .available),
            ],
            tariff: Tariff(pricePerKWhSatang: 900, sessionFeeSatang: 1000),
            supportsDrones: false
        ),
        Station(
            id: "stn-rai-01",
            name: "Suphanburi Drone Field",
            address: "Suphanburi rice plains",
            latitude: 14.4744,
            longitude: 100.1177,
            connectors: [
                Connector(id: "stn-rai-01-c1", kind: .drone, standard: .droneXT60, powerKW: 5, status: .available),
                Connector(id: "stn-rai-01-c2", kind: .drone, standard: .droneXT90, powerKW: 8, status: .available),
            ],
            tariff: Tariff(pricePerKWhSatang: 600, sessionFeeSatang: 500),
            supportsDrones: true
        ),
        Station(
            id: "stn-mix-01",
            name: "Korat AgriDepot Hybrid",
            address: "Mueang Nakhon Ratchasima",
            latitude: 14.9799,
            longitude: 102.0978,
            connectors: [
                Connector(id: "stn-mix-01-c1", kind: .ev, standard: .ccs2, powerKW: 60, status: .available),
                Connector(id: "stn-mix-01-c2", kind: .drone, standard: .droneXT90, powerKW: 8, status: .faulted),
            ],
            tariff: Tariff(pricePerKWhSatang: 720, sessionFeeSatang: 0),
            supportsDrones: true
        ),
    ]
}
