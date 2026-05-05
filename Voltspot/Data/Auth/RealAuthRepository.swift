import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Production auth repository backed by Firebase Authentication.
///
/// Token persistence + refresh is handled internally by FirebaseAuth — the
/// SDK keeps its own Keychain entry under `<bundle>.firebaseauth`. We do
/// **not** mirror tokens into `KeychainStore`; the Gateway API client will
/// fetch a fresh ID token via `Auth.auth().currentUser?.getIDToken()` at
/// request time.
///
/// First sign-in / sign-up writes a `/users/{uid}` document so the rest of
/// the app can attach `role`, `displayName`, and `fcmToken` to a known
/// record.
actor RealAuthRepository: AuthRepository {

    private let auth: Auth
    private let db: Firestore

    init(auth: Auth = .auth(), db: Firestore = .firestore()) {
        self.auth = auth
        self.db = db
    }

    func signIn(email: String, password: String) async throws -> User {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            try await ensureUserDoc(for: result.user)
            return Self.map(result.user)
        } catch {
            throw Self.translate(error)
        }
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> User {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            if let displayName, !displayName.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = displayName
                try await change.commitChanges()
            }
            try await ensureUserDoc(for: result.user)
            return Self.map(result.user)
        } catch {
            throw Self.translate(error)
        }
    }

    func signOut() async {
        try? auth.signOut()
    }

    func currentUser() async -> User? {
        guard let firebaseUser = auth.currentUser else { return nil }
        return Self.map(firebaseUser)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws -> User {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: nil
        )
        do {
            let result = try await auth.signIn(with: credential)
            if let fullName, !fullName.isEmpty,
               (result.user.displayName ?? "").isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = fullName
                try await change.commitChanges()
            }
            try await ensureUserDoc(for: result.user)
            return Self.map(result.user)
        } catch {
            throw Self.translate(error)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> User {
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        do {
            let result = try await auth.signIn(with: credential)
            try await ensureUserDoc(for: result.user)
            return Self.map(result.user)
        } catch {
            throw Self.translate(error)
        }
    }

    private func ensureUserDoc(for fbUser: FirebaseAuth.User) async throws {
        let ref = db.collection("users").document(fbUser.uid)
        let snap = try await ref.getDocument()
        guard !snap.exists else { return }
        var data: [String: Any] = [
            "email": fbUser.email ?? "",
            "role": NSNull(),
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let displayName = fbUser.displayName, !displayName.isEmpty {
            data["displayName"] = displayName
        }
        try await ref.setData(data)
    }

    private static func map(_ fbUser: FirebaseAuth.User) -> User {
        User(
            id: fbUser.uid,
            email: fbUser.email ?? "",
            displayName: fbUser.displayName.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func translate(_ error: Error) -> Error {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: ns.code) else {
            // URLError surfaces here when the request never reaches Firebase
            // (airplane mode, captive portal). Most useful to the user as a
            // network message rather than the generic "unknown" fallback.
            if (error as NSError).domain == NSURLErrorDomain {
                return AuthError.networkUnavailable
            }
            return error
        }
        switch code {
        case .invalidEmail, .wrongPassword, .userNotFound, .invalidCredential:
            return AuthError.invalidCredentials
        case .emailAlreadyInUse, .credentialAlreadyInUse:
            return AuthError.emailAlreadyInUse
        case .weakPassword:
            return AuthError.weakPassword
        case .networkError:
            return AuthError.networkUnavailable
        case .tooManyRequests:
            return AuthError.tooManyRequests
        case .userDisabled:
            return AuthError.userDisabled
        default:
            return AuthError.unknown
        }
    }
}
