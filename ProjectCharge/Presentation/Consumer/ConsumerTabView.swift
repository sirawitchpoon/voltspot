import SwiftUI

struct ConsumerTabView: View {
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
