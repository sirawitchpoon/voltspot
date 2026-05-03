import FirebaseCore
import SwiftUI

@main
struct VoltspotApp: App {
    @State private var session: AppSession
    @State private var locale: LocalePreference

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
        _locale = State(initialValue: LocalePreference())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(locale)
                .environment(\.locale, locale.locale)
                .onOpenURL { url in
                    _ = GoogleSignInCoordinator.handle(url: url)
                }
                .task {
                    await GoogleSignInCoordinator.restorePreviousSignInIfNeeded()
                }
        }
    }
}
