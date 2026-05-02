import Foundation

// Schema: RemoteStopTransaction.json
struct RemoteStopTransactionRequest: Codable, Sendable, Equatable {
    let transactionId: Int
}

// Schema: RemoteStopTransactionResponse.json
struct RemoteStopTransactionResponse: Codable, Sendable, Equatable {
    let status: OCPPRemoteStartStopStatus
}
