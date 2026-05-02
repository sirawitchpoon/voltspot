import Foundation

/// High-level OCPP client. Wraps `WebSocketManager`, correlates Calls with
/// CallResults by uniqueId, and surfaces unsolicited (server-initiated)
/// Calls as a stream for the UI to react to.
///
/// Typical use from a future Partner diagnostic view:
/// ```swift
/// let client = OCPPClient(url: ..., chargePointIdentity: "CP001")
/// try await client.connect()
/// let resp: BootNotificationResponse = try await client.call(
///     action: .bootNotification,
///     payload: BootNotificationRequest(...)
/// )
/// for await incoming in client.incomingCalls {
///     // handle RemoteStartTransaction etc.
/// }
/// ```
actor OCPPClient {
    private let manager: WebSocketManager
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var incomingContinuation: AsyncStream<IncomingCall>.Continuation?
    private(set) var incomingCalls: AsyncStream<IncomingCall>!

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    struct IncomingCall: Sendable {
        let uniqueId: String
        let action: String
        let payload: Data
    }

    init(url: URL, chargePointIdentity: String) {
        self.manager = WebSocketManager(
            url: url,
            chargePointIdentity: chargePointIdentity
        )
        var localContinuation: AsyncStream<IncomingCall>.Continuation!
        self.incomingCalls = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.incomingContinuation = localContinuation
    }

    func connect() async {
        let stream = await manager.connect()
        Task { [weak self] in
            for await envelope in stream {
                await self?.handle(envelope)
            }
        }
    }

    func disconnect() async {
        await manager.disconnect()
        for (_, c) in pending {
            c.resume(throwing: OCPPTransportError.notConnected)
        }
        pending.removeAll()
        incomingContinuation?.finish()
    }

    /// Send a Call and await its CallResult. Action-specific request and
    /// response types are passed by the caller; this method handles the
    /// envelope and correlation.
    func call<Req: Encodable & Sendable, Res: Decodable & Sendable>(
        action: OCPPAction,
        payload: Req,
        responseType: Res.Type = Res.self
    ) async throws -> Res {
        let uniqueId = UUID().uuidString
        let payloadData = try encoder.encode(payload)
        let envelope = OCPPEnvelope.call(
            uniqueId: uniqueId,
            action: action.rawValue,
            payload: payloadData
        )
        try await manager.send(envelope)
        let resultData = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            pending[uniqueId] = c
        }
        return try decoder.decode(Res.self, from: resultData)
    }

    /// Reply to a Call we received from the server with a CallResult.
    func reply<T: Encodable & Sendable>(to uniqueId: String, payload: T) async throws {
        let payloadData = try encoder.encode(payload)
        try await manager.send(.callResult(uniqueId: uniqueId, payload: payloadData))
    }

    private func handle(_ envelope: OCPPEnvelope) {
        switch envelope {
        case let .callResult(uniqueId, payload):
            guard let c = pending.removeValue(forKey: uniqueId) else { return }
            c.resume(returning: payload)
        case let .callError(uniqueId, code, description, _):
            guard let c = pending.removeValue(forKey: uniqueId) else { return }
            c.resume(throwing: OCPPCallErrorReceived(code: code, description: description))
        case let .call(uniqueId, action, payload):
            incomingContinuation?.yield(
                IncomingCall(uniqueId: uniqueId, action: action, payload: payload)
            )
        }
    }
}

struct OCPPCallErrorReceived: Error, Sendable {
    let code: OCPPCallErrorCode
    let description: String
}
