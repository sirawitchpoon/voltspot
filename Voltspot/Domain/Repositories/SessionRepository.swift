import Foundation

protocol SessionRepository: Sendable {
    func recentSessions(limit: Int) async throws -> [ChargingSession]
    func startSession(stationId: String, connectorId: String) async throws -> ChargingSession
    func stopSession(id: String) async throws -> ChargingSession

    /// Sessions across every station owned by the signed-in partner
    /// in the half-open range `[from, to)`. Drives Partner Earnings
    /// + Dashboard. Filters server-side on the denormalised
    /// `partnerId` field so the Firestore security rule (which only
    /// permits reads where `partnerId == auth.uid`) can authorise
    /// the query without a cross-collection join.
    func partnerSessions(from: Date, to: Date) async throws -> [ChargingSession]
}
