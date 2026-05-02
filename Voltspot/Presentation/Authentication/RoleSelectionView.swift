import SwiftUI

struct RoleSelectionView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: RoleSelectionViewModel?

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    BrandHeader(subtitle: "role.subtitle")
                        .padding(.top, AppSpacing.xxl)

                    Text("role.prompt")
                        .font(.appText(20, weight: .semibold))
                        .foregroundStyle(Color.appFg)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)

                    VStack(spacing: AppSpacing.md) {
                        RoleCard(
                            kind: .consumer,
                            icon: "bolt.car.fill",
                            title: "role.consumer.title",
                            subtitle: "role.consumer.body"
                        ) { viewModel?.select(.consumer) }

                        RoleCard(
                            kind: .partner,
                            icon: "building.2.fill",
                            title: "role.partner.title",
                            subtitle: "role.partner.body"
                        ) { viewModel?.select(.partner) }
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    Spacer(minLength: AppSpacing.xl)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RoleSelectionViewModel(session: session)
            }
        }
    }
}

private struct RoleCard: View {
    enum Kind { case consumer, partner }

    let kind: Kind
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    private var tint: Color { kind == .consumer ? .appAccent : .appClay }
    private var tintBg: Color { kind == .consumer ? .appAccentTint : .appClay.opacity(0.12) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(tintBg)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appText(17, weight: .semibold))
                        .foregroundStyle(Color.appFg)
                    Text(subtitle)
                        .font(.appText(13))
                        .foregroundStyle(Color.appFg3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appFg3)
            }
            .padding(AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(Color.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(Color.appRule, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
