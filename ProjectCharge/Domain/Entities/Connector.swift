import Foundation

enum ConnectorKind: String, Codable, Sendable {
    case ev
    case drone
}

enum ConnectorStandard: String, Codable, Sendable {
    case type2          // EV AC
    case ccs2           // EV DC
    case chademo        // EV DC
    case droneXT60      // Agricultural drone (placeholder)
    case droneXT90      // Agricultural drone (placeholder)
}

enum ConnectorStatus: String, Codable, Sendable {
    case available
    case occupied
    case faulted
    case unavailable
}

struct Connector: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let kind: ConnectorKind
    let standard: ConnectorStandard
    let powerKW: Double
    let status: ConnectorStatus
}
