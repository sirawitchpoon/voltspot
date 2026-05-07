import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

/// Observable that backs `SessionView`. Subscribes to two Firestore
/// listeners:
///
/// 1. `/sessions where userId == currentUid && status == "active"`
///    drives `activeSession` so the screen reactively flips between
///    "no session" and "live session" when the gateway writes.
/// 2. `/connector_status/{stationId}_{connectorId}` — only attached
///    while a session is active — surfaces a banner if the charger
///    flips to `Faulted` mid-session, with the OCPP error code so
///    the user knows what to do (unplug, retry, contact support).
///
/// Two listeners instead of one because the schemas don't share a
/// natural join key — sessions are addressed by transactionId,
/// connector_status by station+connector — and Firestore queries
/// don't cross collections.
///
/// Single-session assumption: most Thai EV chargers gate access via
/// OCPP idTag, and the Gateway's pending-starts mechanism only
/// creates one /sessions doc per remote-start. If concurrent
/// sessions are ever added, replace `activeSession` with `[…]`.
@MainActor
@Observable
final class SessionViewModel {
    /// The currently active session, or `nil` if the user isn't
    /// charging. Driven entirely by the Firestore listener.
    var activeSession: ChargingSession?

    /// True while `stop()` is in flight.
    var isStopping: Bool = false

    /// Last user-visible error from `stop()`, cleared when the user
    /// retries or a new session arrives.
    var errorMessage: String?

    /// Surface for connector-fault banner. `nil` when the charger
    /// is healthy; populated when the connector_status listener
    /// observes a non-NoError errorCode + non-Charging status.
    var connectorAlert: ConnectorAlert?

    private let repository: any SessionRepository
    private let db: Firestore
    private var sessionListener: ListenerRegistration?
    private var connectorListener: ListenerRegistration?

    /// Tracks which connector_status doc we're currently subscribed
    /// to, keyed by `{stationId}_{connectorId}`. Lets us avoid a
    /// detach+reattach when the active session changes shape but the
    /// underlying connector hasn't.
    private var connectorListenerKey: String?

    init(
        repository: any SessionRepository = RealSessionRepository(),
        db: Firestore = .firestore()
    ) {
        self.repository = repository
        self.db = db
    }

    /// Attaches the active-session listener. Idempotent — calling
    /// twice during `.task` re-runs is safe because we detach first.
    /// The fault listener attaches lazily inside the session
    /// callback so it always points at the right connector.
    func startObserving() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        sessionListener?.remove()
        sessionListener = db.collection("sessions")
            .whereField("userId", isEqualTo: uid)
            .whereField("status", isEqualTo: "active")
            .order(by: "startTime", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let doc = snapshot?.documents.first
                let session = doc.flatMap(RealSessionRepository.decodeSession)
                self.activeSession = session
                self.refreshConnectorListener(for: session)
            }
    }

    func stopObserving() {
        sessionListener?.remove()
        sessionListener = nil
        connectorListener?.remove()
        connectorListener = nil
        connectorListenerKey = nil
        connectorAlert = nil
    }

    /// Issues a remote stop and waits for the doc to flip to a
    /// terminal status. The session listener will clear
    /// `activeSession` on its own; the connector listener
    /// auto-detaches via `refreshConnectorListener(for: nil)`.
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

    // MARK: - Connector-status listener

    /// Subscribes / re-subscribes the connector_status listener to
    /// match the currently active session, or detaches when there's
    /// no session. Cheap to call repeatedly because it only re-binds
    /// when the underlying station+connector key actually changes.
    private func refreshConnectorListener(for session: ChargingSession?) {
        guard let session else {
            connectorListener?.remove()
            connectorListener = nil
            connectorListenerKey = nil
            connectorAlert = nil
            return
        }

        let key = "\(session.stationId)_\(session.connectorId)"
        if key == connectorListenerKey { return }

        connectorListener?.remove()
        connectorListenerKey = key
        connectorListener = db.collection("connector_status").document(key)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else { return }
                let status = (data["status"] as? String) ?? ""
                let errorCode = (data["errorCode"] as? String) ?? "NoError"
                let info = data["info"] as? String

                // Decision rule:
                //   - status=Faulted        → fault banner
                //   - errorCode!=NoError    → fault banner (charger
                //                             reporting trouble even
                //                             if it lets the session
                //                             continue)
                //   - status=Unavailable mid-session — also a fault
                //     case (charger admin-disabled or self-disabled)
                //   - everything else clears the banner.
                let isFault = status == "Faulted"
                    || status == "Unavailable"
                    || (errorCode != "NoError" && errorCode != "")
                if isFault {
                    self.connectorAlert = ConnectorAlert(
                        status: status,
                        errorCode: errorCode,
                        info: info
                    )
                } else {
                    self.connectorAlert = nil
                }
            }
    }
}

/// Snapshot of a problem the charger reported on the active
/// session's connector. View renders this as an inline banner.
struct ConnectorAlert: Equatable, Sendable {
    let status: String
    let errorCode: String
    let info: String?
}
