import Foundation

/// OCPP-J wraps every message in a JSON array whose first element is the
/// MessageTypeId. Per spec section 4.2.
enum OCPPMessageType: Int, Sendable {
    case call = 2
    case callResult = 3
    case callError = 4
}
