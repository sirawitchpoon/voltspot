import Foundation

/// All OCPP 1.6 action names that this client understands. Names match the
/// `Action` field on the wire — preserve casing exactly.
enum OCPPAction: String, Sendable {
    case bootNotification = "BootNotification"
    case heartbeat = "Heartbeat"
    case statusNotification = "StatusNotification"
    case authorize = "Authorize"
    case startTransaction = "StartTransaction"
    case stopTransaction = "StopTransaction"
    case meterValues = "MeterValues"
    case remoteStartTransaction = "RemoteStartTransaction"
    case remoteStopTransaction = "RemoteStopTransaction"
    case dataTransfer = "DataTransfer"
}
