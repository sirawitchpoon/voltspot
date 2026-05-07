import Foundation
import Observation

/// Backs the "Recent sessions" section on `ConsumerProfileView`.
/// Pulls the last few completed sessions from `SessionRepository`
/// (which queries `/sessions where userId == currentUid orderBy
/// startTime desc`).
///
/// Why a separate view model instead of inlining the load on the
/// view: the list reload should not run on every `body` re-render
/// (which the env locale toggle triggers, for example), and we want
/// `isLoading` + `errorMessage` to live somewhere observable. The
/// alternative — a `.task` on the section view — fires on every
/// appearance which is fine but doesn't expose the intermediate
/// states we need for skeletons.
@MainActor
@Observable
final class ConsumerProfileViewModel {
    /// Most recent sessions for the signed-in user. Empty until
    /// `load()` finishes.
    var sessions: [ChargingSession] = []

    /// True while the listing query is in flight.
    var isLoading: Bool = false

    /// Last user-visible error from the listing query. Cleared on
    /// the next successful load.
    var errorMessage: String?

    private let repository: any SessionRepository

    init(repository: any SessionRepository = RealSessionRepository()) {
        self.repository = repository
    }

    /// Fetches the latest sessions. Idempotent — safe to call from
    /// `.task` on every appearance; the existing list is replaced
    /// only when the new fetch succeeds.
    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await repository.recentSessions(limit: 10)
        } catch let error as GatewayError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
