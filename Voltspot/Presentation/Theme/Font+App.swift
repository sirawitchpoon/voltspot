import SwiftUI

extension Font {
    static func appText(_ size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Sarabun-Bold"
        case .semibold: name = "Sarabun-SemiBold"
        case .medium: name = "Sarabun-Medium"
        default: name = "Sarabun-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func appMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "IBMPlexMono-SemiBold"
        case .medium: name = "IBMPlexMono-Medium"
        default: name = "IBMPlexMono-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static var appTitle: Font { appText(28, weight: .bold) }
    static var appHeadline: Font { appText(20, weight: .semibold) }
    static var appSubheadline: Font { appText(16, weight: .medium) }
    static var appBody: Font { appText(15) }
    static var appCallout: Font { appText(14) }
    static var appCaption: Font { appText(12) }
    static var appMonoNumber: Font { appMono(15, weight: .medium) }
    static var appMonoLarge: Font { appMono(28, weight: .semibold) }
}
