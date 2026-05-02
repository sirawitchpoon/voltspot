import SwiftUI

struct SessionView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: AppSpacing.lg) {
                    ZStack {
                        Circle()
                            .fill(Color.appSurface2)
                            .frame(width: 140, height: 140)
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(Color.appFg3)
                    }
                    VStack(spacing: AppSpacing.sm) {
                        Text("session.empty.title")
                            .font(.appText(20, weight: .semibold))
                            .foregroundStyle(Color.appFg)
                        Text("session.empty.description")
                            .font(.appText(14))
                            .foregroundStyle(Color.appFg3)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                }
            }
            .navigationTitle("consumer.tab.session")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
