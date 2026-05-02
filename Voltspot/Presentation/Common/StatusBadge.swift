import SwiftUI

enum StatusBadgeStyle {
    case available, inUse, fault, offline

    var color: Color {
        switch self {
        case .available: return .appSuccess
        case .inUse: return .appWarning
        case .fault: return .appDanger
        case .offline: return .appGray
        }
    }
}

struct StatusBadge: View {
    let style: StatusBadgeStyle
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(style.color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.appText(12, weight: .semibold))
                .foregroundStyle(style.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(style.color.opacity(0.18), in: Capsule())
    }
}
