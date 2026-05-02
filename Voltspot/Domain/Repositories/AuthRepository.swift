import Foundation

protocol AuthRepository: Sendable {
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String, displayName: String?) async throws -> User
    func signOut() async
    func currentUser() async -> User?
}

enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case emailAlreadyInUse
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return String(localized: "auth.error.invalidCredentials")
        case .emailAlreadyInUse:
            return String(localized: "auth.error.emailAlreadyInUse")
        case .unknown:
            return String(localized: "auth.error.unknown")
        }
    }
}
