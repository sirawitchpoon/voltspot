import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

/// Observable that backs `SessionView`. Subscribes to a Firestore
/// listener on `/sessions` filtered to the current Firebase user +
/// `status == "active"` so the screen reactively flips between
/// "no session" and "live session" without the user navigating.
///
/// One charging-eligible session per user at a time is assumed
/// (most Thai EV chargers gate the user via OCPP idTag, and the
/// Gateway's pending-starts mechanism only ever creates one /sessions
/// doc per remote-start request). If a future product flow allows
/// concurrent sessions, replace `activeSession` with `[ChargingSession]`.
@MainActor
@Observable
final class SessionViewModel {
    /// The currently active session, or `nil` if the user isn't
    /// charging. Driven entirely by the Firestore listener.
    var activeSession: ChargingSession?

    /// True while `stop()` is in flight.
    var isStopping: Bool = false

    /// Last user-visible error, cleared when the user retries or a
    /// new session arrives.
    var errorMessage: String?

    private let repository: any SessionRepository
    private let db: Firestore
    private var listener: ListenerRegistration?

    init(
        repository: any SessionRepository = RealSessionRepository(),
        db: Firestore = .firestore()
    ) {
        self.repository = repository
        self.db = db
    }

    /// Attaches the listener. Idempotent — calling twice during
    /// `.task` re-runs is safe because we detach first.
    func startObserving() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("sessions")
            .whereField("userId", isEqualTo: uid)
            .whereField("status", isEqualTo: "active")
            .order(by: "startTime", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let doc = snapshot?.documents.first
                if let doc {
                    self.activeSession = RealSessionRepository.decodeSession(doc)
                } else {
                    self.activeSession = nil
                }
            }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
    }

    /// Issues a remote stop and waits for the doc to flip to a
    /// terminal status. The listener will already have cleared
    /// `activeSession` on its own once status leaves "active", so
    /// the UI reverts to the empty state automatically.
    func stop() async {
        guard let session = activeSession else { return }
        errorMessage = nil
        isStopping = true
        defer { isStopping = false }
        do {
            _ = try await repository.stopSession(id: session.id)
        } catch let error as GatewayError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
