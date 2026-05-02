import SwiftUI

/// Renders the brand title using `AppConfig.appName`. Use this anywhere a
/// brand label is needed so renaming flows from a single source.
struct BrandHeader: View {
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 4) {
            Text(AppConfig.appName)
                .font(.largeTitle.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
