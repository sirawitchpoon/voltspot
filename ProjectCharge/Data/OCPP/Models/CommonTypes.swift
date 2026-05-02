import Foundation

// MARK: - Shared enums (OCPP 1.6 spec)

enum OCPPRegistrationStatus: String, Codable, Sendable {
    case accepted = "Accepted"
    case pending = "Pending"
    case rejected = "Rejected"
}

enum OCPPAuthorizationStatus: String, Codable, Sendable {
    case accepted = "Accepted"
    case blocked = "Blocked"
    case expired = "Expired"
    case invalid = "Invalid"
    case concurrentTx = "ConcurrentTx"
}

enum OCPPChargePointErrorCode: String, Codable, Sendable {
    case connectorLockFailure = "ConnectorLockFailure"
    case evCommunicationError = "EVCommunicationError"
    case groundFailure = "GroundFailure"
    case highTemperature = "HighTemperature"
    case internalError = "InternalError"
    case localListConflict = "LocalListConflict"
    case noError = "NoError"
    case otherError = "OtherError"
    case overCurrentFailure = "OverCurrentFailure"
    case powerMeterFailure = "PowerMeterFailure"
    case powerSwitchFailure = "PowerSwitchFailure"
    case readerFailure = "ReaderFailure"
    case resetFailure = "ResetFailure"
    case underVoltage = "UnderVoltage"
    case overVoltage = "OverVoltage"
    case weakSignal = "WeakSignal"
}

enum OCPPChargePointStatus: String, Codable, Sendable {
    case available = "Available"
    case preparing = "Preparing"
    case charging = "Charging"
    case suspendedEVSE = "SuspendedEVSE"
    case suspendedEV = "SuspendedEV"
    case finishing = "Finishing"
    case reserved = "Reserved"
    case unavailable = "Unavailable"
    case faulted = "Faulted"
}

enum OCPPRemoteStartStopStatus: String, Codable, Sendable {
    case accepted = "Accepted"
    case rejected = "Rejected"
}

enum OCPPDataTransferStatus: String, Codable, Sendable {
    case accepted = "Accepted"
    case rejected = "Rejected"
    case unknownMessageId = "UnknownMessageId"
    case unknownVendorId = "UnknownVendorId"
}

enum OCPPStopReason: String, Codable, Sendable {
    case emergencyStop = "EmergencyStop"
    case evDisconnected = "EVDisconnected"
    case hardReset = "HardReset"
    case local = "Local"
    case other = "Other"
    case powerLoss = "PowerLoss"
    case reboot = "Reboot"
    case remote = "Remote"
    case softReset = "SoftReset"
    case unlockCommand = "UnlockCommand"
    case deAuthorized = "DeAuthorized"
}

// MARK: - IdTagInfo

struct OCPPIdTagInfo: Codable, Sendable, Equatable {
    let expiryDate: Date?
    let parentIdTag: String?
    let status: OCPPAuthorizationStatus
}

// MARK: - MeterValue

struct OCPPSampledValue: Codable, Sendable, Equatable {
    let value: String
    let context: String?
    let format: String?
    let measurand: String?
    let phase: String?
    let location: String?
    let unit: String?
}

struct OCPPMeterValue: Codable, Sendable, Equatable {
    let timestamp: Date
    let sampledValue: [OCPPSampledValue]
}
