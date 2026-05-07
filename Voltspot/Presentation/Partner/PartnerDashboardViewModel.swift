import FirebaseAuth
import Foundation
import Observation

/// Backs `PartnerDashboardView`. Pulls the same partner stations +
/// today's sessions roll-up that `MyStationsViewModel` does, plus a
/// month-to-date gross figure for the headline tile and the most
/// recent activity list. We don't share state across these two
/// view models because each screen owns its own load lifecycle and
/// can be on screen independently.
@MainActor
@Observable
final class PartnerDashboardViewModel {
    var stations: [Station] = []
    var todaySessions: [ChargingSession] = []
    var monthGrossSatang: Int = 0
    var recentActivity: [ChargingSession] = []

    var isLoading: Bool = false
    var errorMessage: String?

    private let stationRepo: any StationRepository
    private let sessionRepo: any SessionRepository

    init(
        stationRepo: any StationRepository = RealStationRepository(),
        sessionRepo: any SessionRepository = RealSessionRepository()
    ) {
        self.stationRepo = stationRepo
        self.sessionRepo = sessionRepo
    }

    var sessionsTodayCount: Int { todaySessions.count }
    var energyTodayKWh: Double { todaySessions.reduce(0) { $0 + $1.energyKWh } }
    var activeStationsLabel: String {
        let live = stations.filter { station in
            station.connectors.contains { $0.status == .available || $0.status == .occupied }
        }.count
        return "\(live) / \(stations.count)"
    }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "common.error.signInRequired"
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let owned = try await stationRepo.partnerStations(ownerId: uid)
            self.stations = owned

            guard !owned.isEmpty else {
                self.todaySessions = []
                self.monthGrossSatang = 0
                self.recentActivity = []
                return
            }

            let (todayFrom, todayTo) = Self.todayBounds()
            let (monthFrom, monthTo) = Self.monthBounds()

            async let todayTask = sessionRepo.partnerSessions(
                stationIds: owned.map(\.id), from: todayFrom, to: todayTo)
            async let monthTask = sessionRepo.partnerSessions(
                stationIds: owned.map(\.id), from: monthFrom, to: monthTo)

            let today = try await todayTask
            let month = try await monthTask
            self.todaySessions = today
            self.monthGrossSatang = month.reduce(0) { $0 + $1.costSatang }
            // Most recent five sessions across the month for the
            // activity list. Falls back to "today" when the month
            // hasn't accumulated enough yet.
            self.recentActivity = Array(month.prefix(5))
        } catch let error as GatewayError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stationName(for id: String) -> String {
        stations.first(where: { $0.id == id })?.name ?? id
    }

    private static func todayBounds() -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    private static func monthBounds() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
        return (start, end)
    }
}
