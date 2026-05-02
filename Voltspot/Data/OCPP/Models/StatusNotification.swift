import Foundation

// Schema: StatusNotification.json
struct StatusNotificationRequest: Codable, Sendable, Equatable {
    let connectorId: Int
    let errorCode: OCPPChargePointErrorCode
    let info: String?
    let status: OCPPChargePointStatus
    let timestamp: Date?
    let vendorId: String?
    let vendorErrorCode: String?
}

// Schema: StatusNotificationResponse.json (empty payload)
struct StatusNotificationResponse: Codable, Sendable, Equatable {}
