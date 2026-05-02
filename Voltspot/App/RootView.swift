import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var didBootstrap = false

    var body: some View {
        Group {
            if !didBootstrap {
                LoadingView()
            } else {
                switch (session.user, session.role) {
                case (nil, _):
                    AuthView()
                case (.some, nil):
                    RoleSelectionView()
                case (.some, .consumer):
                    ConsumerTabView()
                case (.some, .partner):
                    PartnerTabView()
                }
            }
        }
        .tint(.appAccent)
        .task {
            guard !didBootstrap else { return }
            await session.bootstrap()
            didBootstrap = true
        }
    }
}
