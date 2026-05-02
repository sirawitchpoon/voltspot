import SwiftUI

struct AppShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let card = AppShadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    static let elevated = AppShadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 8)
}

extension View {
    func appShadow(_ shadow: AppShadow = .card) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
