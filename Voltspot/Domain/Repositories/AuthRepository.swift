import Foundation

protocol AuthRepository: Sendable {
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String, displayName: String?) async throws -> User
    func signOut() async
    func currentUser() async -> User?

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws -> User
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> User
}

extension AuthRepository {
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws -> User {
        throw AuthError.federatedNotSupported
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> User {
        throw AuthError.federatedNotSupported
    }
}

enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkUnavailable
    case tooManyRequests
    case userDisabled
    case federatedNotSupported
    case federatedTokenMissing
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return String(localized: "auth.error.invalidCredentials")
        case .emailAlreadyInUse:
            return String(localized: "auth.error.emailAlreadyInUse")
        case .weakPassword:
            return String(localized: "auth.error.weakPassword")
        case .networkUnavailable:
            return String(localized: "auth.error.networkUnavailable")
        case .tooManyRequests:
            return String(localized: "auth.error.tooManyRequests")
        case .userDisabled:
            return String(localized: "auth.error.userDisabled")
        case .federatedNotSupported:
            return String(localized: "auth.error.federatedNotSupported")
        case .federatedTokenMissing:
            return String(localized: "auth.error.federatedTokenMissing")
        case .unknown:
            return String(localized: "auth.error.unknown")
        }
    }
}
