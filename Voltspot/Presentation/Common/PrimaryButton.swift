import SwiftUI

struct PrimaryButton: View {
    let title: LocalizedStringKey
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.appBg)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.appText(16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .foregroundStyle(Color.appBg)
            .background(
                (isDisabled ? Color.appAccent.opacity(0.4) : Color.appAccent),
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
