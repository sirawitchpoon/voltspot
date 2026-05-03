import FirebaseFirestore
import Foundation

/// Firestore-backed `UserProfileRepository`.
///
/// Operates on `/users/{uid}` documents that `RealAuthRepository`
/// creates at first sign-in. Writes are merge-style so we never
/// stomp other fields (`email`, `displayName`, `createdAt`,
/// `fcmToken`).
///
/// `@unchecked Sendable` because Firebase's `Firestore` is thread-safe
/// per the SDK docs but is not yet annotated `Sendable`. Same pattern
/// `RealStationRepository` uses.
struct RealUserProfileRepository: UserProfileRepository, @unchecked Sendable {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func setRole(_ role: UserRole, for uid: String) async throws {
        try await db.collection("users").document(uid).setData(
            ["role": role.rawValue],
            merge: true
        )
    }

    func currentRole(for uid: String) async throws -> UserRole? {
        let snap = try await db.collection("users").document(uid).getDocument()
        guard let raw = snap.data()?["role"] as? String else { return nil }
        return UserRole(rawValue: raw)
    }

    func clearRole(for uid: String) async throws {
        try await db.collection("users").document(uid).setData(
            ["role": NSNull()],
            merge: true
        )
    }
}
