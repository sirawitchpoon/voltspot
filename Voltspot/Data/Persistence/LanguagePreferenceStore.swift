import Foundation

/// Persists the user's chosen UI language as a 2-letter ISO code in
/// `UserDefaults`. Mirrors `RolePreferenceStore` — local only, no
/// cross-device sync because language is a per-device preference.
struct LanguagePreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "preferredLanguage") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns the saved code or `nil` to fall back to the system locale.
    func loadLanguage() -> String? {
        defaults.string(forKey: key)
    }

    func saveLanguage(_ code: String) {
        defaults.set(code, forKey: key)
    }

    func clearLanguage() {
        defaults.removeObject(forKey: key)
    }
}
