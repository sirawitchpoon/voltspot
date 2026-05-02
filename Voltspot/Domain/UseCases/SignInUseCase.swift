import Foundation

struct SignInUseCase: Sendable {
    let authRepository: any AuthRepository

    func callAsFunction(email: String, password: String) async throws -> User {
        try await authRepository.signIn(email: email, password: password)
    }
}
