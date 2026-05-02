import Foundation

// Schema: BootNotification.json (urn:OCPP:1.6:2019:12:BootNotificationRequest)
struct BootNotificationRequest: Codable, Sendable, Equatable {
    let chargePointVendor: String
    let chargePointModel: String
    let chargePointSerialNumber: String?
    let chargeBoxSerialNumber: String?
    let firmwareVersion: String?
    let iccid: String?
    let imsi: String?
    let meterType: String?
    let meterSerialNumber: String?
}

// Schema: BootNotificationResponse.json
struct BootNotificationResponse: Codable, Sendable, Equatable {
    let status: OCPPRegistrationStatus
    let currentTime: Date
    let interval: Int
}
