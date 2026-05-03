import Foundation

/// Cloud-side reads and writes for the per-user profile document
/// (`/users/{uid}` in Firestore). The role chosen in
/// `RoleSelectionView` is the only field the iOS app currently writes
/// here — `RealAuthRepository` populates the rest at sign-up time.
///
/// `RolePreferenceStore` (UserDefaults) acts as a local cache for
/// instant rendering on app launch; this protocol is the authoritative
/// store and lets the role follow the user across devices.
protocol UserProfileRepository: Sendable {
    /// Persists the user's chosen role to the cloud. Idempotent —
    /// safe to call repeatedly with the same value.
    func setRole(_ role: UserRole, for uid: String) async throws

    /// Reads the current role for a user. Returns `nil` when the
    /// user document has no role field yet (e.g. fresh sign-up that
    /// hasn't reached `RoleSelectionView` yet).
    func currentRole(for uid: String) async throws -> UserRole?

    /// Resets the role to `null` server-side. Used when the user
    /// explicitly switches roles via the Profile screen — distinct
    /// from sign-out, which leaves the cloud value intact so the next
    /// sign-in keeps the previous choice.
    func clearRole(for uid: String) async throws
}
