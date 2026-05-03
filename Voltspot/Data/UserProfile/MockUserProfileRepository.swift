import Foundation

/// In-memory `UserProfileRepository` for offline development and tests.
/// Mirrors the `Mock*Repository` siblings — call sites (i.e.
/// `AppSession`) keep talking to the protocol, so swapping back and
/// forth costs nothing.
actor MockUserProfileRepository: UserProfileRepository {
    private var roles: [String: UserRole] = [:]

    func setRole(_ role: UserRole, for uid: String) async throws {
        roles[uid] = role
    }

    func currentRole(for uid: String) async throws -> UserRole? {
        roles[uid]
    }

    func clearRole(for uid: String) async throws {
        roles[uid] = nil
    }
}
