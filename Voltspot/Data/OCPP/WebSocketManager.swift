import Foundation

/// Thin wrapper around `URLSessionWebSocketTask` that streams OCPP-J
/// envelopes. Connection lifecycle:
///
///   connect() ──▶ task.receive() loop ──▶ AsyncStream<OCPPEnvelope>
///   send(_:)  ──▶ task.send(.string(json))
///   disconnect() cancels the task and ends the stream.
///
/// Auto-reconnect with exponential backoff lives one layer up in
/// `OCPPClient`; this manager stays a stateless transport.
actor WebSocketManager {
    private let session: URLSession
    private let url: URL
    private let chargePointIdentity: String
    private let version: OCPPVersion

    private var task: URLSessionWebSocketTask?
    private var inboundContinuation: AsyncStream<OCPPEnvelope>.Continuation?

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

    init(
        url: URL,
        chargePointIdentity: String,
        version: OCPPVersion = .v16J,
        session: URLSession = .shared
    ) {
        // OCPP-J URLs end with the Charge Point identity as the last path
        // segment. We accept either form: caller can pass the full URL
        // including identity, or we'll append it.
        if url.lastPathComponent == chargePointIdentity {
            self.url = url
        } else {
            self.url = url.appendingPathComponent(chargePointIdentity)
        }
        self.chargePointIdentity = chargePointIdentity
        self.version = version
        self.session = session
    }

    func connect() -> AsyncStream<OCPPEnvelope> {
        let stream = AsyncStream<OCPPEnvelope> { continuation in
            self.inboundContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }

        var request = URLRequest(url: url)
        request.setValue(version.subprotocolHeader, forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let newTask = session.webSocketTask(with: request)
        self.task = newTask
        newTask.resume()
        Task { await self.receiveLoop() }

        return stream
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        inboundContinuation?.finish()
        inboundContinuation = nil
    }

    func send(_ envelope: OCPPEnvelope) async throws {
        guard let task else { throw OCPPTransportError.notConnected }
        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw OCPPTransportError.encodingFailure
        }
        try await task.send(.string(json))
    }

    private func receiveLoop() async {
        guard let task else { return }
        do {
            while task.state == .running {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                do {
                    let envelope = try decoder.decode(OCPPEnvelope.self, from: data)
                    inboundContinuation?.yield(envelope)
                } catch {
                    // Drop malformed frames; production code should log.
                    continue
                }
            }
        } catch {
            inboundContinuation?.finish()
        }
    }
}

enum OCPPTransportError: Error, Sendable {
    case notConnected
    case encodingFailure
}
