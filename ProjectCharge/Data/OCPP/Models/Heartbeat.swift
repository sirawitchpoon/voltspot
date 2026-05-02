import Foundation

// Schema: Heartbeat.json (empty payload — uses an explicit struct so that
// the round-trip JSON form is `{}` rather than `null`).
struct HeartbeatRequest: Codable, Sendable, Equatable {}

// Schema: HeartbeatResponse.json
struct HeartbeatResponse: Codable, Sendable, Equatable {
    let currentTime: Date
}
