import MapKit
import SwiftUI

struct StationFinderView: View {
    @State private var viewModel = StationFinderViewModel()

    var body: some View {
        NavigationStack {
            Map(position: $viewModel.cameraPosition) {
                ForEach(viewModel.stations) { station in
                    Annotation(station.name, coordinate: station.coordinate) {
                        Button {
                            viewModel.selectedStation = station
                        } label: {
                            Image(systemName: station.supportsDrones ? "airplane.circle.fill" : "bolt.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                                .background(Circle().fill(.background))
                        }
                    }
                }
            }
            .navigationTitle("consumer.tab.find")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadStations() }
            .sheet(item: $viewModel.selectedStation) { station in
                StationDetailView(station: station)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
