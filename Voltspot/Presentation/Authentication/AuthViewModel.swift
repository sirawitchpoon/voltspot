import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum Mode: Sendable { case signIn, signUp }

    var mode: Mode = .signIn
    var email: String = ""
    var password: String = ""
    var displayName: String = ""
    var errorMessage: String?
    var isWorking: Bool = false

    private let signIn: SignInUseCase
    private let signUp: SignUpUseCase
    private let session: AppSession

    init(signIn: SignInUseCase, signUp: SignUpUseCase, session: AppSession) {
        self.signIn = signIn
        self.signUp = signUp
        self.session = session
    }

    var passwordMeetsMinimum: Bool {
        password.count >= AppConfig.minimumPasswordLength
    }

    var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp { return passwordMeetsMinimum }
        return true
    }

    func submit() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let user: User
            switch mode {
            case .signIn:
                user = try await signIn(email: email, password: password)
            case .signUp:
                user = try await signUp(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            }
            session.applySignedIn(user: user)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
