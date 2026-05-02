import Foundation

struct SignInWithAppleUseCase: Sendable {
    let authRepository: any AuthRepository

    func callAsFunction(idToken: String, rawNonce: String, fullName: String?) async throws -> User {
        try await authRepository.signInWithApple(
            idToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
    }
}
