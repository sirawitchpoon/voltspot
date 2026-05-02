import Foundation
import Security

/// Minimal Keychain wrapper for sensitive tokens. Strings are stored under
/// the bundle identifier as a service prefix.
struct KeychainStore: Sendable {
    private let service: String

    init(service: String? = nil) {
        self.service = service ?? Bundle.main.bundleIdentifier ?? AppConfig.appName
    }

    func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension KeychainStore {
    enum Keys {
        static let authToken = "authToken"
        static let refreshToken = "refreshToken"
    }
}
