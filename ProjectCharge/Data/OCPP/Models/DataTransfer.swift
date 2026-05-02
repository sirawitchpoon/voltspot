import Foundation

// Schema: DataTransfer.json
struct DataTransferRequest: Codable, Sendable, Equatable {
    let vendorId: String
    let messageId: String?
    let data: String?
}

// Schema: DataTransferResponse.json
struct DataTransferResponse: Codable, Sendable, Equatable {
    let status: OCPPDataTransferStatus
    let data: String?
}
