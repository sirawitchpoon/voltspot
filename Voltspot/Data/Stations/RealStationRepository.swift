import CoreLocation
import FirebaseFirestore
import Foundation

/// Firestore-backed station repository.
///
/// Schema lives at `/stations/{id}`; see `deploy/firestore.rules` and the
/// backend setup plan for collection layout. Geo queries use a single
/// geohash prefix range and refine results client-side with great-circle
/// distance — see `Geohash.boundingRange` for the trade-offs.
struct RealStationRepository: StationRepository {

    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func nearbyStations(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Station] {
        let range = Geohash.boundingRange(center: coordinate, radiusKm: radiusKm)
        var query: Query = db.collection("stations").order(by: "geohash")
        if !range.start.isEmpty {
            query = query
                .whereField("geohash", isGreaterThanOrEqualTo: range.start)
                .whereField("geohash", isLessThan: range.end)
        }

        let snapshot = try await query.getDocuments()
        let candidates = snapshot.documents.compactMap { Self.decode(document: $0) }

        let centerLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let radiusMeters = radiusKm * 1000

        return candidates.filter { station in
            let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
            return centerLocation.distance(from: stationLocation) <= radiusMeters
        }
    }

    func station(id: String) async throws -> Station? {
        let snap = try await db.collection("stations").document(id).getDocument()
        guard snap.exists else { return nil }
        return Self.decode(document: snap)
    }

    private static func decode(document: DocumentSnapshot) -> Station? {
        guard let data = document.data() else { return nil }
        guard let name = data["name"] as? String,
              let address = data["address"] as? String else {
            return nil
        }

        let latitude: Double
        let longitude: Double
        if let geo = data["location"] as? GeoPoint {
            latitude = geo.latitude
            longitude = geo.longitude
        } else if let lat = data["latitude"] as? Double, let lng = data["longitude"] as? Double {
            latitude = lat
            longitude = lng
        } else {
            return nil
        }

        let connectorsRaw = data["connectors"] as? [[String: Any]] ?? []
        let connectors = connectorsRaw.compactMap(Self.decodeConnector)

        let tariff = Self.decodeTariff(data["tariff"] as? [String: Any])
        let supportsDrones = (data["supportsDrones"] as? Bool) ?? false

        return Station(
            id: document.documentID,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            connectors: connectors,
            tariff: tariff,
            supportsDrones: supportsDrones
        )
    }

    private static func decodeConnector(_ raw: [String: Any]) -> Connector? {
        guard let id = raw["id"] as? String,
              let kindRaw = raw["kind"] as? String,
              let kind = ConnectorKind(rawValue: kindRaw),
              let standardRaw = raw["standard"] as? String,
              let standard = ConnectorStandard(rawValue: standardRaw),
              let statusRaw = raw["status"] as? String,
              let status = ConnectorStatus(rawValue: statusRaw) else {
            return nil
        }
        let powerKW = (raw["powerKW"] as? Double) ?? 0
        return Connector(id: id, kind: kind, standard: standard, powerKW: powerKW, status: status)
    }

    private static func decodeTariff(_ raw: [String: Any]?) -> Tariff {
        let pricePerKWhSatang = (raw?["pricePerKWhSatang"] as? Int) ?? 0
        let sessionFeeSatang = (raw?["sessionFeeSatang"] as? Int) ?? 0
        return Tariff(pricePerKWhSatang: pricePerKWhSatang, sessionFeeSatang: sessionFeeSatang)
    }
}
