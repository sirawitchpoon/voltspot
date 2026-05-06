import FirebaseAuth
import Foundation

/// Errors surfaced by `GatewayAPIClient`. They map the Gateway's HTTP
/// + transport failure modes to a small set the rest of the app can
/// switch over and present to the user.
enum GatewayError: LocalizedError, Sendable {
    /// User is not signed in (no Firebase ID token available).
    case notAuthenticated
    /// Charger isn't currently connected to the Gateway (HTTP 503).
    case chargerOffline
    /// Charger replied "Rejected" — busy, faulted, or refused this idTag (HTTP 409).
    case chargerRejected
    /// Charger took longer than `CALL_TIMEOUT` to reply (HTTP 504).
    case chargerTimeout
    /// Authentication ID token expired or invalid (HTTP 401). The
    /// Firebase SDK normally refreshes ahead of time — if this fires,
    /// the user has been signed out remotely.
    case authExpired
    /// Network reachability failure or a non-HTTP error.
    case networkUnavailable
    /// Anything else (5xx, malformed responses, unexpected codes).
    case unexpected(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "session.error.notAuthenticated")
        case .chargerOffline:
            return String(localized: "session.error.chargerOffline")
        case .chargerRejected:
            return String(localized: "session.error.chargerRejected")
        case .chargerTimeout:
            return String(localized: "session.error.chargerTimeout")
        case .authExpired:
            return String(localized: "session.error.authExpired")
        case .networkUnavailable:
            return String(localized: "session.error.networkUnavailable")
        case .unexpected(_, let message):
            if let message, !message.isEmpty { return message }
            return String(localized: "session.error.unexpected")
        }
    }
}

/// Minimal HTTP client for the Voltspot OCPP Gateway. Adds a fresh
/// Firebase ID token to every request and translates HTTP status
/// codes into typed `GatewayError` values.
///
/// Why a hand-rolled client instead of a generic networking layer:
/// - We have **two** endpoints today (remote-start, remote-stop) and
///   no plans to grow much past five. A generic abstraction would
///   carry more weight than the bespoke calls.
/// - The error-shape negotiation with the Gateway is intentional;
///   keeping it inline makes the iOS-side error UI easy to inspect.
///
/// All requests are short-lived (the Gateway is supposed to reply
/// within ~10 seconds) — long-lived state (live energy, cost) flows
/// through Firestore listeners instead, not HTTP polling.
struct GatewayAPIClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokenProvider: @Sendable () async throws -> String

    init(
        baseURL: URL = AppConfig.gatewayBaseURL,
        session: URLSession = .shared,
        tokenProvider: @Sendable @escaping () async throws -> String = Self.defaultTokenProvider
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// POST `/api/stations/{stationId}/connectors/{connectorId}/remote-start`.
    /// Returns when the Gateway has confirmed the charger Accepted —
    /// the resulting `ChargingSession` doc materialises in Firestore
    /// shortly after, observed via `RealSessionRepository`.
    func remoteStart(stationID: String, connectorID: String) async throws {
        let connectorIDInt = Int(connectorID) ?? 0
        let url = try buildURL(path: "/api/stations/\(stationID)/connectors/\(connectorIDInt)/remote-start")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        try await execute(request)
    }

    /// POST `/api/sessions/{transactionId}/remote-stop`.
    func remoteStop(transactionID: Int) async throws {
        let url = try buildURL(path: "/api/sessions/\(transactionID)/remote-stop")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try await execute(request)
    }

    private func buildURL(path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GatewayError.unexpected(status: 0, message: "invalid base URL")
        }
        let basePath = components.path.trimmingTrailingSlash
        components.path = basePath + path
        guard let url = components.url else {
            throw GatewayError.unexpected(status: 0, message: "invalid URL components")
        }
        return url
    }

    // MARK: - Private

    /// Executes a request with one retry on transient failures.
    /// Why one retry instead of three: most Gateway failures users
    /// see are deterministic ("charger offline") and retrying just
    /// makes the spinner spin longer. We retry once to cover a
    /// dropped TCP connection / token-refresh race.
    private func execute(_ initial: URLRequest) async throws {
        var lastError: Error?
        for attempt in 0..<2 {
            var request = initial
            do {
                request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
            } catch {
                throw GatewayError.notAuthenticated
            }
            request.timeoutInterval = 15

            let result: (data: Data, response: URLResponse)
            do {
                result = try await session.data(for: request)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == NSURLErrorDomain {
                    lastError = GatewayError.networkUnavailable
                } else {
                    lastError = error
                }
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }
                break
            }
            guard let http = result.response as? HTTPURLResponse else {
                throw GatewayError.unexpected(status: 0, message: "non-HTTP response")
            }
            switch http.statusCode {
            case 200...299:
                return
            case 401:
                throw GatewayError.authExpired
            case 503:
                throw GatewayError.chargerOffline
            case 504:
                throw GatewayError.chargerTimeout
            case 409:
                throw GatewayError.chargerRejected
            case 500...599:
                lastError = GatewayError.unexpected(status: http.statusCode, message: extractMessage(result.data))
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }
            default:
                throw GatewayError.unexpected(status: http.statusCode, message: extractMessage(result.data))
            }
        }
        if let lastError {
            throw lastError
        }
        throw GatewayError.unexpected(status: 0, message: nil)
    }

    /// Pulls the `error` field out of a JSON error body, falling back
    /// to a UTF-8 decode of the raw bytes. The Gateway's
    /// `writeJSONError` always emits `{"error":"..."}`, but we
    /// tolerate other shapes just in case.
    private func extractMessage(_ body: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = json["error"] as? String {
            return message
        }
        return String(data: body, encoding: .utf8)
    }

    /// Default ID-token provider — pulls from the currently signed-in
    /// Firebase user. `forceRefresh: false` lets the SDK reuse a
    /// cached token unless it's near expiry.
    @Sendable
    static func defaultTokenProvider() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw GatewayError.notAuthenticated
        }
        return try await user.getIDToken()
    }
}

private extension String {
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
