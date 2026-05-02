import SwiftUI

struct PartnerTabView: View {
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
            PartnerDashboardView()
                .tabItem { Label("partner.tab.dashboard", systemImage: "chart.bar") }

            MyStationsView()
                .tabItem { Label("partner.tab.stations", systemImage: "building.2") }

            EarningsView()
                .tabItem { Label("partner.tab.earnings", systemImage: "creditcard") }

            PartnerProfileView()
                .tabItem { Label("partner.tab.profile", systemImage: "person.crop.circle") }
        }
    }
}
