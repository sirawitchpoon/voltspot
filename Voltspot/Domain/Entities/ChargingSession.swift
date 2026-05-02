import Foundation

struct ChargingSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let stationId: String
    let connectorId: String
    let startedAt: Date
    let endedAt: Date?
    let energyKWh: Double
    let costSatang: Int
}
