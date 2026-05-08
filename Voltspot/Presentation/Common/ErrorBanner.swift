import SwiftUI

/// Inline error card for view-model surfaces (`errorMessage: String?`).
/// Renders the message with a retry button when a handler is supplied.
/// Used across Partner + Consumer screens to keep error UX consistent
/// — no more bare red `Text("error")` blocks.
struct ErrorBanner: View {
    /// Localised or already-localised message. Pass either a localized
    /// key (when calling sites supply one) or a runtime-resolved
    /// string from a repository error.
    let message: String

    /// Optional retry handler. When nil the banner has no action button.
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appDanger)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("common.error.title")
                    .font(.appText(13, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text(message)
                    .font(.appText(12))
                    .foregroundStyle(Color.appFg3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let onRetry {
                Button(action: onRetry) {
                    Text("common.retry")
                        .font(.appText(12, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.appAccentTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.appDanger.opacity(0.4), lineWidth: 1)
        )
    }
}
