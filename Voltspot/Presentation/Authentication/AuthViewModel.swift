import AuthenticationServices
import Foundation
import Observation
import SwiftUI

struct PasswordRule: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let passed: Bool
}

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
    private let signInWithApple: SignInWithAppleUseCase
    private let signInWithGoogle: SignInWithGoogleUseCase
    private let session: AppSession
    private let appleNonceCache = AppleNonceCache()
    private let googleCoordinator = GoogleSignInCoordinator()

    init(
        signIn: SignInUseCase,
        signUp: SignUpUseCase,
        signInWithApple: SignInWithAppleUseCase,
        signInWithGoogle: SignInWithGoogleUseCase,
        session: AppSession
    ) {
        self.signIn = signIn
        self.signUp = signUp
        self.signInWithApple = signInWithApple
        self.signInWithGoogle = signInWithGoogle
        self.session = session
    }

    /// Live checklist used in sign-up mode. Length + letter + digit follows
    /// NIST 800-63B guidance — length is the strongest factor; we add a
    /// minimal letter/digit check so common-word-only entries get flagged
    /// without making complexity onerous.
    var passwordRules: [PasswordRule] {
        [
            PasswordRule(
                id: "length",
                label: "auth.password.rule.length \(AppConfig.minimumPasswordLength)",
                passed: password.count >= AppConfig.minimumPasswordLength
            ),
            PasswordRule(
                id: "letter",
                label: "auth.password.rule.letter",
                passed: password.range(of: "\\p{L}", options: .regularExpression) != nil
            ),
            PasswordRule(
                id: "number",
                label: "auth.password.rule.number",
                passed: password.range(of: "\\d", options: .regularExpression) != nil
            ),
        ]
    }

    var passwordMeetsAllRules: Bool {
        passwordRules.allSatisfy(\.passed)
    }

    var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp { return passwordMeetsAllRules }
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

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = appleNonceCache.startNew()
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let authorization = try result.get()
            let payload = try AppleAuthorizationParser.extract(from: authorization)
            guard let rawNonce = appleNonceCache.consume() else {
                errorMessage = AuthError.federatedTokenMissing.errorDescription
                return
            }
            let user = try await signInWithApple(
                idToken: payload.idToken,
                rawNonce: rawNonce,
                fullName: payload.fullName
            )
            session.applySignedIn(user: user)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch let error as AppleSignInError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitGoogle() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let tokens = try await googleCoordinator.presentSignIn()
            let user = try await signInWithGoogle(
                idToken: tokens.idToken,
                accessToken: tokens.accessToken
            )
            session.applySignedIn(user: user)
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
