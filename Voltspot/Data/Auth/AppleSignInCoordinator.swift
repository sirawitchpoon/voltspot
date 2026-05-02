import AuthenticationServices
import CryptoKit
import Foundation

/// Helpers for Sign in with Apple — manages the per-attempt nonce that
/// Firebase requires to bind the credential to the device that requested it.
///
/// Usage from a SwiftUI `SignInWithAppleButton`:
/// ```swift
/// SignInWithAppleButton(.signIn) { request in
///     request.nonce = nonceCache.startNew()       // SHA256 hash sent to Apple
///     request.requestedScopes = [.fullName, .email]
/// } onCompletion: { result in
///     Task { await viewModel.handleAppleResult(result) }
/// }
/// ```
@MainActor
final class AppleNonceCache {
    private(set) var rawNonce: String?

    /// Generates a fresh raw nonce, stores it, and returns its SHA256 hash
    /// for embedding in the `ASAuthorizationAppleIDRequest`.
    func startNew() -> String {
        let raw = Self.randomNonceString()
        self.rawNonce = raw
        return Self.sha256(raw)
    }

    /// Returns and clears the held raw nonce. Call this after the
    /// `ASAuthorization` callback to pass the raw nonce to Firebase.
    func consume() -> String? {
        let nonce = rawNonce
        rawNonce = nil
        return nonce
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

/// Decoded data carried out of an `ASAuthorization` containing an Apple ID
/// credential. The `idToken` is the JWT Firebase needs to mint a session.
struct AppleCredentialPayload: Sendable {
    let idToken: String
    let fullName: String?
}

enum AppleSignInError: LocalizedError, Sendable {
    case wrongCredentialType
    case missingIdentityToken
    case missingNonce

    var errorDescription: String? {
        switch self {
        case .wrongCredentialType:
            return String(localized: "auth.error.unknown")
        case .missingIdentityToken, .missingNonce:
            return String(localized: "auth.error.federatedTokenMissing")
        }
    }
}

enum AppleAuthorizationParser {
    static func extract(from authorization: ASAuthorization) throws -> AppleCredentialPayload {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.wrongCredentialType
        }
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw AppleSignInError.missingIdentityToken
        }
        let nameComponents = credential.fullName
        let fullName: String? = {
            guard let nameComponents else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let s = formatter.string(from: nameComponents)
            return s.isEmpty ? nil : s
        }()
        return AppleCredentialPayload(idToken: token, fullName: fullName)
    }
}
