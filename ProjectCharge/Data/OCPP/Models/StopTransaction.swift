import Foundation

// Schema: StopTransaction.json
struct StopTransactionRequest: Codable, Sendable, Equatable {
    let idTag: String?
    let meterStop: Int
    let timestamp: Date
    let transactionId: Int
    let reason: OCPPStopReason?
    let transactionData: [OCPPMeterValue]?
}

// Schema: StopTransactionResponse.json
struct StopTransactionResponse: Codable, Sendable, Equatable {
    let idTagInfo: OCPPIdTagInfo?
}
