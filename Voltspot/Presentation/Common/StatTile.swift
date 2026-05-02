import SwiftUI

struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String? = nil
    var icon: String? = nil
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent ? Color.appAccent : Color.appFg3)
                }
                Text(label)
                    .font(.appText(12, weight: .medium))
                    .foregroundStyle(accent ? Color.appAccent : Color.appFg3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.appMono(22, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                if let unit {
                    Text(unit)
                        .font(.appText(12, weight: .medium))
                        .foregroundStyle(Color.appFg3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(
            (accent ? Color.appAccentTint : Color.appSurface),
            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        )
    }
}
