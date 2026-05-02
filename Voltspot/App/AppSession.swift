import Foundation
import Observation

/// Application-wide auth + role state.
///
/// Injected at the app root via `.environment(AppSession())`. Views read
/// `user` and `role` to drive routing in `RootView`. Mutations go through
/// the `apply…` methods so persistence stays in sync.
@MainActor
@Observable
final class AppSession {
    private(set) var user: User?
    private(set) var role: UserRole?

    private let authRepository: any AuthRepository
    private let rolePreferenceStore: RolePreferenceStore

    init(
        authRepository: any AuthRepository,
        rolePreferenceStore: RolePreferenceStore
    ) {
        self.authRepository = authRepository
        self.rolePreferenceStore = rolePreferenceStore
    }

    func bootstrap() async {
        user = await authRepository.currentUser()
        role = rolePreferenceStore.loadRole()
    }

    func applySignedIn(user: User) {
        self.user = user
        self.role = rolePreferenceStore.loadRole()
    }

    func applyRole(_ newRole: UserRole) {
        rolePreferenceStore.saveRole(newRole)
        self.role = newRole
    }

    func clearRole() {
        rolePreferenceStore.clearRole()
        self.role = nil
    }

    func signOut() async {
        await authRepository.signOut()
        rolePreferenceStore.clearRole()
        self.user = nil
        self.role = nil
    }
}
