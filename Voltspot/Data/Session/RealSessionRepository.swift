import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Production `SessionRepository` that bridges the iOS app to the
/// Voltspot OCPP Gateway + Firestore.
///
/// The Gateway is the only thing allowed to write to `/sessions` per
/// our security rules, so this repo never writes; it POSTs to the
/// Gateway (which forwards to the charger over OCPP) and reads the
/// resulting documents from Firestore.
///
/// Three flows:
///
///   1. `startSession` — POST `/api/.../remote-start`, then **wait**
///      for the matching `/sessions` doc to appear (the Gateway
///      creates it in response to the charger's StartTransaction,
///      typically within a few seconds of Accepted).
///
///   2. `stopSession` — POST `/api/sessions/{txId}/remote-stop`,
///      then wait for the existing doc to flip its `status` field to
///      `completed` (or `interrupted`).
///
///   3. `recentSessions` — straight Firestore query against the
///      composite index defined in `deploy/firestore.indexes.json`.
///
/// `@unchecked Sendable` for the same reason as the other Real
/// repositories — Firestore + URLSession aren't `Sendable`-annotated
/// yet but are documented thread-safe.
struct RealSessionRepository: SessionRepository, @unchecked Sendable {

    let db: Firestore
    let api: GatewayAPIClient

    /// How long `startSession` waits for the gateway-created doc to
    /// appear before giving up. Default 30s — covers normal charger
    /// latency (~5s) plus generous slack for slow ones.
    let startObservationTimeout: TimeInterval

    /// How long `stopSession` waits for the doc to flip status.
    let stopObservationTimeout: TimeInterval

    init(
        db: Firestore = .firestore(),
        api: GatewayAPIClient = GatewayAPIClient(),
        startObservationTimeout: TimeInterval = 30,
        stopObservationTimeout: TimeInterval = 20
    ) {
        self.db = db
        self.api = api
        self.startObservationTimeout = startObservationTimeout
        self.stopObservationTimeout = stopObservationTimeout
    }

    // MARK: - SessionRepository

    func recentSessions(limit: Int) async throws -> [ChargingSession] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw GatewayError.notAuthenticated
        }
        let snapshot = try await db.collection("sessions")
            .whereField("userId", isEqualTo: uid)
            .order(by: "startTime", descending: true)
            .limit(to: max(1, limit))
            .getDocuments()
        return snapshot.documents.compactMap(Self.decodeSession)
    }

    func startSession(stationId: String, connectorId: String) async throws -> ChargingSession {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw GatewayError.notAuthenticated
        }

        let requestSentAt = Date()
        try await api.remoteStart(stationID: stationId, connectorID: connectorId)

        // Race the listener against a timeout. The Gateway writes
        // /sessions/tx-{N} when StartTransaction lands. We filter on
        // `userId == currentUid` (now populated thanks to the Gateway's
        // pending-starts mechanism) AND `stationId` AND
        // `createdAt >= requestSentAt` so two simultaneous requests
        // for the same station can't return the wrong session.
        let query = db.collection("sessions")
            .whereField("userId", isEqualTo: uid)
            .whereField("stationId", isEqualTo: stationId)
            .whereField("status", isEqualTo: "active")
            .order(by: "startTime", descending: true)
            .limit(to: 1)
        return try await waitForSession(matching: query, since: requestSentAt, timeout: startObservationTimeout)
    }

    func stopSession(id: String) async throws -> ChargingSession {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GatewayError.notAuthenticated
        }
        let txID = Self.transactionID(from: id)
        try await api.remoteStop(transactionID: txID)

        // Listen for the same doc flipping to a terminal status.
        let docRef = db.collection("sessions").document(id)
        return try await waitForTerminalStatus(at: docRef, timeout: stopObservationTimeout)
    }

    // MARK: - Private — Firestore listeners with timeout

    /// Subscribes to `query`, completes when a doc matching the
    /// freshness floor (`startTime >= since`) materialises, or
    /// throws on timeout. Detaches the listener in either case.
    private func waitForSession(
        matching query: Query,
        since: Date,
        timeout: TimeInterval
    ) async throws -> ChargingSession {
        try await withThrowingTaskGroup(of: ChargingSession.self) { group in
            // The listener task — yields the first matching doc.
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ChargingSession, Error>) in
                    let listener = ListenerHolder()
                    listener.handle = query.addSnapshotListener { snapshot, error in
                        if let error {
                            listener.detach()
                            cont.resume(throwing: error)
                            return
                        }
                        guard let documents = snapshot?.documents else { return }
                        for doc in documents {
                            guard let session = Self.decodeSession(doc) else { continue }
                            // Filter out stale "active" docs from a
                            // previous session at the same station.
                            if session.startedAt >= since.addingTimeInterval(-1) {
                                listener.detach()
                                cont.resume(returning: session)
                                return
                            }
                        }
                    }
                }
            }
            // The timeout task.
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GatewayError.chargerTimeout
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func waitForTerminalStatus(
        at docRef: DocumentReference,
        timeout: TimeInterval
    ) async throws -> ChargingSession {
        try await withThrowingTaskGroup(of: ChargingSession.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ChargingSession, Error>) in
                    let listener = ListenerHolder()
                    listener.handle = docRef.addSnapshotListener { snapshot, error in
                        if let error {
                            listener.detach()
                            cont.resume(throwing: error)
                            return
                        }
                        guard let snapshot, let data = snapshot.data() else { return }
                        let status = (data["status"] as? String) ?? ""
                        if status == "completed" || status == "interrupted" || status == "failed" {
                            guard let session = Self.decodeSession(snapshot) else {
                                listener.detach()
                                cont.resume(throwing: GatewayError.unexpected(status: 0, message: "decode failed"))
                                return
                            }
                            listener.detach()
                            cont.resume(returning: session)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GatewayError.chargerTimeout
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Decoding

    /// Maps a Firestore session document to the domain
    /// `ChargingSession`. Returns nil if any required field is
    /// missing or malformed.
    static func decodeSession(_ snap: DocumentSnapshot) -> ChargingSession? {
        guard let data = snap.data() else { return nil }
        guard let stationID = data["stationId"] as? String else { return nil }
        let connectorID: String
        switch data["connectorId"] {
        case let v as Int: connectorID = String(v)
        case let v as Int64: connectorID = String(v)
        case let v as String: connectorID = v
        default: return nil
        }
        let startedAt = (data["startTime"] as? Timestamp)?.dateValue() ?? Date()
        let endedAt = (data["endTime"] as? Timestamp)?.dateValue()
        let energyKWh = readDouble(data["energyKWh"])
        let costSatang: Int
        switch data["costSatang"] {
        case let v as Int: costSatang = v
        case let v as Int64: costSatang = Int(v)
        case let v as Double: costSatang = Int(v) // shouldn't happen — Firestore stores Int as Int64
        default: costSatang = 0
        }
        return ChargingSession(
            id: snap.documentID,
            stationId: stationID,
            connectorId: connectorID,
            startedAt: startedAt,
            endedAt: endedAt,
            energyKWh: energyKWh,
            costSatang: costSatang
        )
    }

    private static func readDouble(_ v: Any?) -> Double {
        switch v {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as Int64: return Double(n)
        default: return 0
        }
    }

    /// Document IDs are `tx-{N}`. Strip the prefix to recover the
    /// integer the Gateway needs in the URL.
    static func transactionID(from id: String) -> Int {
        if id.hasPrefix("tx-"), let n = Int(id.dropFirst("tx-".count)) {
            return n
        }
        return Int(id) ?? 0
    }
}

/// Box around a `ListenerRegistration` so the closure can detach
/// itself once the result is delivered. Without the indirection, a
/// captured listener variable would have to be optional + manually
/// managed across the closure boundary.
private final class ListenerHolder: @unchecked Sendable {
    var handle: ListenerRegistration?

    func detach() {
        handle?.remove()
        handle = nil
    }
}
