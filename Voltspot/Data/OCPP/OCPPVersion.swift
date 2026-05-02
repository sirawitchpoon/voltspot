import Foundation

/// OCPP protocol version supported by this client.
///
/// Version is parsed from the URN in every JSON schema in
/// `OCPP_1.6_documentation_2019_12/schemas/json/*.json` — each schema
/// declares `"id": "urn:OCPP:1.6:2019:12:<MessageName>"`. The `1.6` segment
/// is canonical; the date `2019:12` identifies the errata release.
///
/// To support newer versions (e.g. 2.0.1), add a case here, the matching
/// `subprotocolHeader`, and a parallel set of message models.
enum OCPPVersion: String, Sendable {
    case v16J = "1.6"

    /// Value for the `Sec-WebSocket-Protocol` header. The OCPP-J spec
    /// requires this exact identifier.
    var subprotocolHeader: String {
        switch self {
        case .v16J: return "ocpp1.6"
        }
    }
}
