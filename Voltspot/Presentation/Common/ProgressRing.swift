import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 200
    var lineWidth: CGFloat = 18
    var tint: Color = .appAccent
    var trackColor: Color = .appSurface2

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.7), tint]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .frame(width: size, height: size)
    }
}
