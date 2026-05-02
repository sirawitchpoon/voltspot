import SwiftUI

struct SessionView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "session.empty.title",
                systemImage: "bolt.slash",
                description: Text("session.empty.description")
            )
            .navigationTitle("consumer.tab.session")
        }
    }
}
