import SwiftUI

struct ConsumerTabView: View {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "AppSurface")
        appearance.shadowColor = UIColor(named: "AppRule")
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            StationFinderView()
                .tabItem { Label("consumer.tab.find", systemImage: "map") }

            SessionView()
                .tabItem { Label("consumer.tab.session", systemImage: "bolt") }

            ConsumerProfileView()
                .tabItem { Label("consumer.tab.profile", systemImage: "person.crop.circle") }
        }
    }
}
