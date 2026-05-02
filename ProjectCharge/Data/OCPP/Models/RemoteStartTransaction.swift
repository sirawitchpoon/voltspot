import Foundation

// Schema: RemoteStartTransaction.json
//
// chargingProfile is intentionally omitted from this scaffold — it's a
// large nested structure used for demand-response scheduling. Add it when
// the partner UI needs to send/inspect smart-charging profiles.
struct RemoteStartTransactionRequest: Codable, Sendable, Equatable {
    let connectorId: Int?
    let idTag: String
}

// Schema: RemoteStartTransactionResponse.json
struct RemoteStartTransactionResponse: Codable, Sendable, Equatable {
    let status: OCPPRemoteStartStopStatus
}
