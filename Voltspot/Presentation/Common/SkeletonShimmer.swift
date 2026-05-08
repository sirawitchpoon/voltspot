import SwiftUI

/// Lightweight shimmer placeholder for loading cards. Renders as a
/// rounded rectangle with a moving highlight that loops forever; the
/// view is purely cosmetic and never blocks input.
///
/// Use over `if isLoading` branches that previously rendered a blank
/// or `ProgressView` — keeps the layout stable so screens don't
/// jump when data lands.
struct SkeletonShimmer: View {
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.appSurface2)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.35),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.4)
                .offset(x: phase * width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Conditionally swaps a view for a skeleton shimmer. Use on
    /// individual cells so loading state is granular instead of
    /// blanking out the whole screen.
    @ViewBuilder
    func redactedShimmer(_ isLoading: Bool, cornerRadius: CGFloat = 8) -> some View {
        if isLoading {
            SkeletonShimmer(cornerRadius: cornerRadius)
        } else {
            self
        }
    }
}
