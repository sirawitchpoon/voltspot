import SwiftUI

/// Small segmented capsule that lets the user flip between Thai and
/// English on demand. Reads + writes through the `LocalePreference`
/// injected from `VoltspotApp`, so every toggle re-renders the SwiftUI
/// hierarchy via the `\.locale` environment.
///
/// Two visual flavours:
/// - `.compact` (default) — fits unobtrusively into a navigation
///   toolbar or hero overlay
/// - `.row` — full-width strip suited to a Profile "Preferences"
///   section
struct LanguageToggle: View {
    enum Style {
        case compact
        case row
    }

    @Environment(LocalePreference.self) private var preference
    let style: Style

    init(style: Style = .compact) {
        self.style = style
    }

    var body: some View {
        switch style {
        case .compact:
            compactBody
        case .row:
            rowBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 0) {
            languageChip("th", display: "TH")
            languageChip("en", display: "EN")
        }
        .padding(2)
        .background(Color.appSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.appRule, lineWidth: 1))
        .appShadow(.card)
    }

    private var rowBody: some View {
        HStack {
            Text("preferences.language")
                .font(.appText(14))
                .foregroundStyle(Color.appFg3)
            Spacer()
            HStack(spacing: 0) {
                rowChip("th", display: "ไทย")
                rowChip("en", display: "English")
            }
            .padding(2)
            .background(Color.appSurface2, in: Capsule())
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private func languageChip(_ code: String, display: String) -> some View {
        let isActive = preference.current == code
        return Button {
            preference.set(code)
        } label: {
            Text(display)
                .font(.appText(11, weight: .semibold))
                .foregroundStyle(isActive ? Color.appBg : Color.appFg2)
                .frame(width: 32, height: 26)
                .background(
                    isActive ? Color.appAccent : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(code == "th" ? "language.thai" : "language.english"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func rowChip(_ code: String, display: String) -> some View {
        let isActive = preference.current == code
        return Button {
            preference.set(code)
        } label: {
            Text(display)
                .font(.appText(13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.appBg : Color.appFg2)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 6)
                .background(
                    isActive ? Color.appAccent : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
