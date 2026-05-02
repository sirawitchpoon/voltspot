import Foundation

struct SignInWithGoogleUseCase: Sendable {
    let authRepository: any AuthRepository

    func callAsFunction(idToken: String, accessToken: String) async throws -> User {
        try await authRepository.signInWithGoogle(
            idToken: idToken,
            accessToken: accessToken
        )
    }
}
