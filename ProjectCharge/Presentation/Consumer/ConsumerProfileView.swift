import SwiftUI

struct ConsumerProfileView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = session.user {
                        LabeledContent("profile.email", value: user.email)
                        if let name = user.displayName {
                            LabeledContent("profile.displayName", value: name)
                        }
                    }
                    LabeledContent("profile.role", value: String(localized: "role.consumer.title"))
                }

                Section {
                    Button("profile.switchRole") {
                        session.clearRole()
                    }
                    Button("profile.signOut", role: .destructive) {
                        Task { await session.signOut() }
                    }
                } footer: {
                    Text(verbatim: "\(AppConfig.appName) · \(AppConfig.supportEmail)")
                        .font(.caption)
                }
            }
            .navigationTitle("consumer.tab.profile")
        }
    }
}
