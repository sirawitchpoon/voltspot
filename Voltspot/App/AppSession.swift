import Foundation
import Observation

/// Application-wide auth + role state.
///
/// Injected at the app root via `.environment(AppSession())`. Views read
/// `user` and `role` to drive routing in `RootView`. Mutations go through
/// the `apply…` methods so persistence stays in sync.
///
/// Role storage is a two-tier setup: `UserProfileRepository` is the
/// authoritative source (cloud, follows the user across devices) and
/// `RolePreferenceStore` (UserDefaults) is a local cache used to render
/// instantly on launch before the network round-trip completes.
@MainActor
@Observable
final class AppSession {
    private(set) var user: User?
    private(set) var role: UserRole?

    private let authRepository: any AuthRepository
    private let userProfileRepository: any UserProfileRepository
    private let rolePreferenceStore: RolePreferenceStore

    init(
        authRepository: any AuthRepository,
        userProfileRepository: any UserProfileRepository,
        rolePreferenceStore: RolePreferenceStore
    ) {
        self.authRepository = authRepository
        self.userProfileRepository = userProfileRepository
        self.rolePreferenceStore = rolePreferenceStore
    }

    func bootstrap() async {
        user = await authRepository.currentUser()
        role = rolePreferenceStore.loadRole()

        guard let uid = user?.id else { return }
        if let cloudRole = try? await userProfileRepository.currentRole(for: uid) {
            if cloudRole != role {
                role = cloudRole
                rolePreferenceStore.saveRole(cloudRole)
            }
        }
    }

    func applySignedIn(user: User) {
        self.user = user
        self.role = rolePreferenceStore.loadRole()
        Task { [weak self, uid = user.id] in
            guard let self else { return }
            guard let cloudRole = try? await self.userProfileRepository.currentRole(for: uid) else { return }
            if cloudRole != self.role {
                self.role = cloudRole
                self.rolePreferenceStore.saveRole(cloudRole)
            }
        }
    }

    func applyRole(_ newRole: UserRole) {
        rolePreferenceStore.saveRole(newRole)
        self.role = newRole
        guard let uid = user?.id else { return }
        Task { [userProfileRepository] in
            try? await userProfileRepository.setRole(newRole, for: uid)
        }
    }

    func clearRole() {
        rolePreferenceStore.clearRole()
        self.role = nil
        guard let uid = user?.id else { return }
        Task { [userProfileRepository] in
            try? await userProfileRepository.clearRole(for: uid)
        }
    }

    func signOut() async {
        await authRepository.signOut()
        rolePreferenceStore.clearRole()
        self.user = nil
        self.role = nil
        // Cloud role is preserved — next sign-in restores it from Firestore.
    }
}
