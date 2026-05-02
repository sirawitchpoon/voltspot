import Foundation

struct User: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let email: String
    let displayName: String?
}
