import SwiftUI

struct WeavePattern: View {
    var spacing: CGFloat = 14
    var lineWidth: CGFloat = 1
    var tint: Color = .appAccent
    var opacity: Double = 0.08

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let span = size.width + size.height
            var x: CGFloat = -size.height
            while x < span {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += spacing
            }
            context.stroke(path, with: .color(tint.opacity(opacity)), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
