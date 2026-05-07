import Foundation

protocol SessionRepository: Sendable {
    func recentSessions(limit: Int) async throws -> [ChargingSession]
    func startSession(stationId: String, connectorId: String) async throws -> ChargingSession
    func stopSession(id: String) async throws -> ChargingSession

    /// Completed (or active) sessions across the given station IDs in
    /// the half-open range `[from, to)`. Drives Partner Earnings +
    /// Dashboard. Caller passes their owned station IDs from
    /// `StationRepository.partnerStations(...)`.
    ///
    /// Implementations should chunk the `stationIds` list to honour
    /// Firestore's 30-element `in` limit and merge the results.
    func partnerSessions(stationIds: [String], from: Date, to: Date) async throws -> [ChargingSession]
}
