import FirebaseAuth
import Foundation
import Observation

/// Backs `EarningsView`. Aggregates the signed-in partner's sessions
/// across the current calendar month into the headline gross /
/// commission / net trio and a 30-day binned series for the bar
/// chart. Commission is computed at display time from a single rate
/// constant — once a partner-tier system exists, hoist the rate to
/// the partner profile.
@MainActor
@Observable
final class EarningsViewModel {
    /// All sessions in the current month across all owned stations,
    /// sorted descending by `startedAt`.
    var monthSessions: [ChargingSession] = []

    /// Number of sessions in the trailing 30 days, indexed by day
    /// offset from `Date()`. `bins[0]` is today, `bins[29]` is 29
    /// days ago. Empty until `load()` returns.
    var dailyRevenueSatang: [Int] = Array(repeating: 0, count: 30)

    var isLoading: Bool = false
    var errorMessage: String?

    /// Platform commission as a fraction of gross. Hardcoded to 15%
    /// to match the rate in the pitch deck; lift to partner profile
    /// when partner tiers ship.
    let commissionRate: Double = 0.15

    private let stationRepo: any StationRepository
    private let sessionRepo: any SessionRepository

    init(
        stationRepo: any StationRepository = RealStationRepository(),
        sessionRepo: any SessionRepository = RealSessionRepository()
    ) {
        self.stationRepo = stationRepo
        self.sessionRepo = sessionRepo
    }

    /// `gross` and `net` use banker's rounding via `Int` arithmetic
    /// (satang) so they never drift across renders. Display layer
    /// converts to baht via `Decimal` at the boundary.
    var grossSatang: Int { monthSessions.reduce(0) { $0 + $1.costSatang } }
    var commissionSatang: Int { Int(Double(grossSatang) * commissionRate) }
    var netSatang: Int { grossSatang - commissionSatang }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "common.error.signInRequired"
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let stations = try await stationRepo.partnerStations(ownerId: uid)
            guard !stations.isEmpty else {
                self.monthSessions = []
                self.dailyRevenueSatang = Array(repeating: 0, count: 30)
                return
            }

            let (from, to) = Self.monthBounds()
            let sessions = try await sessionRepo.partnerSessions(
                stationIds: stations.map(\.id),
                from: from,
                to: to
            )
            self.monthSessions = sessions

            // Trailing 30 days for the bar chart. We bin by start date
            // in the local calendar — close enough for a visual.
            let chart = try await sessionRepo.partnerSessions(
                stationIds: stations.map(\.id),
                from: Self.thirtyDaysAgo(),
                to: to
            )
            self.dailyRevenueSatang = Self.bin(sessions: chart)
        } catch let error as GatewayError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func monthBounds() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
        return (start, end)
    }

    private static func thirtyDaysAgo() -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -29, to: start) ?? start
    }

    /// Returns 30 buckets (today at index 0, 29 days ago at index 29)
    /// of total revenue in satang.
    private static func bin(sessions: [ChargingSession]) -> [Int] {
        var bins = Array(repeating: 0, count: 30)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for session in sessions {
            let day = cal.startOfDay(for: session.startedAt)
            guard let offsetDays = cal.dateComponents([.day], from: day, to: today).day else {
                continue
            }
            if (0..<30).contains(offsetDays) {
                bins[offsetDays] += session.costSatang
            }
        }
        return bins
    }
}
