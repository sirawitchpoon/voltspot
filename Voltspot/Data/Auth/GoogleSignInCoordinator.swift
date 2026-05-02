import FirebaseCore
import GoogleSignIn
import UIKit

/// Wraps GoogleSignIn-iOS so the rest of the app sees a single `async`
/// method that returns ID + access tokens ready to exchange with Firebase.
///
/// `GIDSignIn.signIn(withPresenting:)` is UIKit-based — it needs a
/// `UIViewController` to present its consent sheet. We resolve the active
/// foreground window's root view controller at call time.
@MainActor
final class GoogleSignInCoordinator {

    /// Tokens returned by Google after a successful consent.
    struct Tokens: Sendable {
        let idToken: String
        let accessToken: String
    }

    /// Configures GoogleSignIn with the OAuth client ID embedded in
    /// `GoogleService-Info.plist`. Call once at app launch (after
    /// `FirebaseApp.configure()`).
    static func configure() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            assertionFailure("Missing Firebase clientID — is GoogleService-Info.plist present?")
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// Restores a prior Google sign-in if one exists (silent — no UI).
    static func restorePreviousSignInIfNeeded() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    /// Presents the Google consent sheet and returns the resulting tokens.
    func presentSignIn() async throws -> Tokens {
        let presenter = try Self.topViewController()
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.federatedTokenMissing
        }
        return Tokens(
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let root = scenes.first?.keyWindow?.rootViewController else {
            throw AuthError.federatedTokenMissing
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
