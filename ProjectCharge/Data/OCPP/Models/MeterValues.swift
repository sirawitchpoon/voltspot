import Foundation

// Schema: MeterValues.json
struct MeterValuesRequest: Codable, Sendable, Equatable {
    let connectorId: Int
    let transactionId: Int?
    let meterValue: [OCPPMeterValue]
}

// Schema: MeterValuesResponse.json (empty payload)
struct MeterValuesResponse: Codable, Sendable, Equatable {}
