import SwiftUI

struct ClayButton: View {
    let title: LocalizedStringKey
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.appText(16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .foregroundStyle(.white)
            .background(
                Color.appClay,
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
