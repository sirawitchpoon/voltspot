import SwiftUI

struct RoleSelectionView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: RoleSelectionViewModel?

    var body: some View {
        VStack(spacing: 24) {
            BrandHeader(subtitle: "role.subtitle")
                .padding(.top, 40)

            Text("role.prompt")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                RoleCard(
                    role: .consumer,
                    icon: "bolt.car.fill",
                    title: "role.consumer.title",
                    subtitle: "role.consumer.body"
                ) { viewModel?.select(.consumer) }

                RoleCard(
                    role: .partner,
                    icon: "building.2.fill",
                    title: "role.partner.title",
                    subtitle: "role.partner.body"
                ) { viewModel?.select(.partner) }
            }
            .padding(.horizontal)

            Spacer()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RoleSelectionViewModel(session: session)
            }
        }
    }
}

private struct RoleCard: View {
    let role: UserRole
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
