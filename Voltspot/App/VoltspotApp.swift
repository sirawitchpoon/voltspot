import SwiftUI

@main
struct VoltspotApp: App {
    @State private var session: AppSession

    init() {
        let auth = MockAuthRepository(keychain: KeychainStore())
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
        }
    }
}
