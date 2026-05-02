import FirebaseCore
import SwiftUI

@main
struct VoltspotApp: App {
    @State private var session: AppSession

    init() {
        FirebaseApp.configure()
        GoogleSignInCoordinator.configure()

        let auth = RealAuthRepository()
        let rolePref = RolePreferenceStore()
        _session = State(initialValue: AppSession(
            authRepository: auth,
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
