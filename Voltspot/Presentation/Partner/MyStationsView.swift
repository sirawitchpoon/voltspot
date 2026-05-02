import CoreLocation
import SwiftUI

struct MyStationsView: View {
    @State private var stations: [Station] = []

    var body: some View {
        NavigationStack {
            List(stations) { station in
                VStack(alignment: .leading) {
                    Text(station.name).font(.headline)
                    Text(station.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("partner.tab.stations")
            .overlay {
                if stations.isEmpty {
                    ContentUnavailableView(
                        "partner.stations.empty.title",
                        systemImage: "building.2",
                        description: Text("partner.stations.empty.description")
                    )
                }
            }
            .task {
                stations = (try? await MockStationRepository().nearbyStations(
                    near: .init(
                        latitude: AppConfig.defaultMapCenterLat,
                        longitude: AppConfig.defaultMapCenterLon
                    ),
                    radiusKm: 1500
                )) ?? []
            }
        }
    }
}
