import Foundation

/// In-memory auth repository for scaffold-time development.
///
/// Persists a fake bearer token in the Keychain so the user remains "signed
/// in" across app launches. Replace with a real backend implementation
/// (Firebase, custom REST, etc.) without changing call sites — they all
/// depend on `AuthRepository`.
actor MockAuthRepository: AuthRepository {
    private let keychain: KeychainStore
    private var cached: User?

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func signIn(email: String, password: String) async throws -> User {
        guard !email.isEmpty, password.count >= AppConfig.minimumPasswordLength else {
            throw AuthError.invalidCredentials
        }
        let user = User(
            id: "mock-\(email.hashValue)",
            email: email,
            displayName: nil
        )
        keychain.set(UUID().uuidString, for: KeychainStore.Keys.authToken)
        cached = user
        return user
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> User {
        guard !email.isEmpty, password.count >= AppConfig.minimumPasswordLength else {
            throw AuthError.invalidCredentials
        }
        let user = User(
            id: "mock-\(email.hashValue)",
            email: email,
            displayName: displayName
        )
        keychain.set(UUID().uuidString, for: KeychainStore.Keys.authToken)
        cached = user
        return user
    }

    func signOut() async {
        keychain.remove(KeychainStore.Keys.authToken)
        keychain.remove(KeychainStore.Keys.refreshToken)
        cached = nil
    }

    func currentUser() async -> User? {
        if let cached { return cached }
        guard keychain.get(KeychainStore.Keys.authToken) != nil else { return nil }
        let restored = User(id: "restored-mock", email: "user@example.com", displayName: nil)
        cached = restored
        return restored
    }
}
