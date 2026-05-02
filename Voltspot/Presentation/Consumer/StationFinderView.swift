import MapKit
import SwiftUI

struct StationFinderView: View {
    @State private var viewModel = StationFinderViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $viewModel.cameraPosition) {
                    ForEach(viewModel.stations) { station in
                        Annotation(station.name, coordinate: station.coordinate) {
                            StationMarker(station: station) {
                                viewModel.selectedStation = station
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("consumer.tab.find")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.loadStations() }
            .sheet(item: $viewModel.selectedStation) { station in
                StationDetailView(station: station)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }
}

private struct StationMarker: View {
    let station: Station
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 44, height: 44)
                    .appShadow(.card)
                Circle()
                    .fill(station.supportsDrones ? Color.appClay : Color.appAccent)
                    .frame(width: 36, height: 36)
                Image(systemName: station.supportsDrones ? "airplane" : "bolt.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.appBg)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
