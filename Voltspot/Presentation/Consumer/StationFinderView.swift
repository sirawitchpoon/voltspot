import MapKit
import SwiftUI

struct StationFinderView: View {
    @State private var viewModel = StationFinderViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
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
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.updateRegion(context.region)
                }

                ZoomControls(
                    onZoomIn: { viewModel.zoomIn() },
                    onZoomOut: { viewModel.zoomOut() }
                )
                .padding(.trailing, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxl)
            }
            .navigationTitle("consumer.tab.find")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.loadInitialStations() }
            .sheet(item: $viewModel.selectedStation) { station in
                StationDetailView(station: station)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }
}

private struct ZoomControls: View {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZoomButton(systemImage: "plus", label: "map.zoomIn", action: onZoomIn)
            Rectangle()
                .fill(Color.appRule)
                .frame(width: 44, height: 1)
            ZoomButton(systemImage: "minus", label: "map.zoomOut", action: onZoomOut)
        }
        .background(
            Color.appSurface,
            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
        )
        .appShadow(.card)
    }
}

private struct ZoomButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appFg)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(label))
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
