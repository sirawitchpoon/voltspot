import FirebaseCore
import SwiftUI

@main
struct VoltspotApp: App {
    @State private var session: AppSession

    init() {
        FirebaseApp.configure()
        GoogleSignInCoordinator.configure()

        let auth = RealAuthRepository()
        let profile = RealUserProfileRepository()
        let rolePref = RolePreferenceStore()
        _session = State(initialValue: AppSession(
            authRepository: auth,
            userProfileRepository: profile,
            rolePreferenceStore: rolePref
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { url in
                    _ = GoogleSignInCoordinator.handle(url: url)
                }
                .task {
                    await GoogleSignInCoordinator.restorePreviousSignInIfNeeded()
                }
        }
    }
}
