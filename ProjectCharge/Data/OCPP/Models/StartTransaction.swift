import Foundation

// Schema: StartTransaction.json
struct StartTransactionRequest: Codable, Sendable, Equatable {
    let connectorId: Int
    let idTag: String
    let meterStart: Int
    let reservationId: Int?
    let timestamp: Date
}

// Schema: StartTransactionResponse.json
struct StartTransactionResponse: Codable, Sendable, Equatable {
    let idTagInfo: OCPPIdTagInfo
    let transactionId: Int
}
