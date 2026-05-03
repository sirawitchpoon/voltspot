import SwiftUI

struct PartnerProfileView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        if let user = session.user {
                            ProfileAvatarHeader(
                                displayName: user.displayName ?? user.email,
                                email: user.email,
                                roleLabel: "role.partner.title",
                                badgeStyle: .inUse
                            )
                        }

                        ProfileSection(title: "profile.section.account") {
                            if let user = session.user {
                                ProfileRow(label: "profile.email", value: user.email)
                                if let name = user.displayName {
                                    ProfileRow(label: "profile.displayName", value: name)
                                }
                            }
                            ProfileRow(label: "profile.role", value: String(localized: "role.partner.title"))
                        }

                        ProfileSection(title: "profile.section.preferences") {
                            LanguageToggle(style: .row)
                        }

                        ProfileSection(title: "profile.section.actions") {
                            ProfileButton(label: "profile.switchRole", icon: "arrow.triangle.2.circlepath") {
                                session.clearRole()
                            }
                            ProfileButton(label: "profile.signOut", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                                Task { await session.signOut() }
                            }
                        }

                        Text(verbatim: "\(AppConfig.appName) · \(AppConfig.supportEmail)")
                            .font(.appText(11))
                            .foregroundStyle(Color.appFg3)
                            .padding(.top, AppSpacing.sm)
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("partner.tab.profile")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
