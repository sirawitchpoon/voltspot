import SwiftUI

struct ConsumerProfileView: View {
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
                                roleLabel: "role.consumer.title",
                                badgeStyle: .available
                            )
                        }

                        ProfileSection(title: "profile.section.account") {
                            if let user = session.user {
                                ProfileRow(label: "profile.email", value: user.email)
                                if let name = user.displayName {
                                    ProfileRow(label: "profile.displayName", value: name)
                                }
                            }
                            ProfileRow(label: "profile.role", value: String(localized: "role.consumer.title"))
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
            .navigationTitle("consumer.tab.profile")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct ProfileAvatarHeader: View {
    let displayName: String
    let email: String
    let roleLabel: LocalizedStringKey
    let badgeStyle: StatusBadgeStyle

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.appAccent, Color.appClay],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text(initials.isEmpty ? "?" : initials)
                    .font(.appText(22, weight: .bold))
                    .foregroundStyle(Color.appBg)
            }
            .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.appText(18, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text(email)
                    .font(.appText(13))
                    .foregroundStyle(Color.appFg3)
            }

            StatusBadge(style: badgeStyle, label: roleLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
    }
}

struct ProfileSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.appText(12, weight: .semibold))
                .foregroundStyle(Color.appFg3)
                .textCase(.uppercase)
                .padding(.leading, AppSpacing.sm)
            VStack(spacing: 0) {
                content
            }
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(Color.appRule, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.appText(14))
                .foregroundStyle(Color.appFg3)
            Spacer()
            Text(value)
                .font(.appText(14, weight: .medium))
                .foregroundStyle(Color.appFg)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.appRule).frame(height: 0.5)
                .padding(.leading, AppSpacing.lg)
        }
    }
}

struct ProfileButton: View {
    let label: LocalizedStringKey
    let icon: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(label)
                    .font(.appText(14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appFg3)
            }
            .foregroundStyle(destructive ? Color.appDanger : Color.appFg)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
