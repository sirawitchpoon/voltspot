import Foundation

protocol SessionRepository: Sendable {
    func recentSessions(limit: Int) async throws -> [ChargingSession]
    func startSession(stationId: String, connectorId: String) async throws -> ChargingSession
    func stopSession(id: String) async throws -> ChargingSession
}
