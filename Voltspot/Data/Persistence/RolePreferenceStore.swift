import Foundation

/// Persists the user's role choice in `UserDefaults`. Role is non-sensitive
/// — choosing Consumer vs Partner doesn't grant capabilities, the backend
/// authoritatively scopes data.
struct RolePreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "selectedRole") {
        self.defaults = defaults
        self.key = key
    }

    func loadRole() -> UserRole? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return UserRole(rawValue: raw)
    }

    func saveRole(_ role: UserRole) {
        defaults.set(role.rawValue, forKey: key)
    }

    func clearRole() {
        defaults.removeObject(forKey: key)
    }
}
