import Foundation

struct SignUpUseCase: Sendable {
    let authRepository: any AuthRepository

    func callAsFunction(email: String, password: String, displayName: String?) async throws -> User {
        try await authRepository.signUp(email: email, password: password, displayName: displayName)
    }
}
