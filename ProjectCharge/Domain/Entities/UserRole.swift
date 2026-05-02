import Foundation

enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case consumer
    case partner

    var id: String { rawValue }
}
