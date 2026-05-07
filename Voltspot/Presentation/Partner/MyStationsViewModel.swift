import FirebaseAuth
import Foundation
import Observation

/// Backs `MyStationsView` — pulls the signed-in partner's own
/// stations from Firestore and the day-to-date sessions across them
/// so each card can show a real "live now / energy today / revenue
/// today" trio instead of hardcoded placeholders.
///
/// The view model deliberately fans out two independent queries
/// (`partnerStations` and `partnerSessions`) and joins them in
/// memory, because Firestore can't do the JOIN itself and partner
/// portfolios are small enough that round-tripping them isn't a
/// concern.
@MainActor
@Observable
final class MyStationsViewModel {
    /// Stations owned by the signed-in partner, sorted by name.
    var stations: [Station] = []

    /// Per-station roll-up for the current calendar day (local time).
    /// Keyed by `stationId`; missing entries render as zeros.
    var todayByStation: [String: PartnerDailyRollup] = [:]

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

    /// Idempotent — safe to call from `.task` on every appearance.
    /// On error we keep whatever data is already loaded so the screen
    /// doesn't blank out on a transient network blip.
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
                self.todayByStation = [:]
                return
            }

            let (from, to) = Self.todayBounds()
            let sessions = try await sessionRepo.partnerSessions(from: from, to: to)
            self.todayByStation = Dictionary(grouping: sessions, by: \.stationId)
                .mapValues(PartnerDailyRollup.init(sessions:))
        } catch let error as GatewayError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `[startOfDay, startOfNextDay)` in the user's calendar — keeps
    /// "today" intuitive even when crossing midnight UTC.
    private static func todayBounds() -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

/// Per-station aggregate for "today" — kept in baht (display-side)
/// because the satang-to-baht conversion happens once at fold time
/// rather than per-row in the view.
struct PartnerDailyRollup: Equatable, Sendable {
    let sessionCount: Int
    let energyKWh: Double
    let revenueSatang: Int

    init(sessions: [ChargingSession]) {
        self.sessionCount = sessions.count
        self.energyKWh = sessions.reduce(0) { $0 + $1.energyKWh }
        self.revenueSatang = sessions.reduce(0) { $0 + $1.costSatang }
    }
}
