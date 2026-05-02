import SwiftUI

/// Renders the brand title using `AppConfig.appName`. Use this anywhere a
/// brand label is needed so renaming flows from a single source.
struct BrandHeader: View {
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 72, height: 72)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.appBg)
            }
            VStack(spacing: 4) {
                Text(AppConfig.appName)
                    .font(.appText(28, weight: .bold))
                    .foregroundStyle(Color.appFg)
                if let subtitle {
                    Text(subtitle)
                        .font(.appText(14))
                        .foregroundStyle(Color.appFg3)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
