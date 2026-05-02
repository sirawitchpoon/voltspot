import SwiftUI

extension ConnectorKind {
    var tintColor: Color { self == .ev ? .appAccent : .appClay }
    var chipBackground: Color { self == .ev ? .appAccentTint : .appClay.opacity(0.15) }
}

struct ConnectorChip: View {
    let abbrev: String
    let kind: ConnectorKind
    var size: CGFloat = 44

    var body: some View {
        Text(abbrev)
            .font(.appMono(12, weight: .semibold))
            .foregroundStyle(kind.tintColor)
            .frame(width: size, height: size)
            .background(kind.chipBackground, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
