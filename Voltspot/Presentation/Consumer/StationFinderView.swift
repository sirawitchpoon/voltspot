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
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.updateRegion(context.region)
                }

                VStack {
                    if let banner = currentBanner {
                        StationStatusBanner(
                            kind: banner,
                            onRetry: banner == .error ? {
                                Task { await viewModel.retry() }
                            } : nil
                        )
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        ZoomControls(
                            onZoomIn: { viewModel.zoomIn() },
                            onZoomOut: { viewModel.zoomOut() }
                        )
                    }
                    .padding(.trailing, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .animation(.easeOut(duration: 0.2), value: viewModel.stations.isEmpty)
                .animation(.easeOut(duration: 0.2), value: viewModel.loadError != nil)
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

    private var currentBanner: StationStatusBanner.Kind? {
        if viewModel.loadError != nil { return .error }
        if !viewModel.isLoading, viewModel.stations.isEmpty { return .empty }
        return nil
    }
}

private struct StationStatusBanner: View {
    enum Kind { case empty, error }

    let kind: Kind
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: kind == .empty ? "mappin.slash" : "wifi.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .empty ? "stations.empty.title" : "stations.error.title")
                    .font(.appText(13, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text(kind == .empty ? "stations.empty.description" : "stations.error.description")
                    .font(.appText(11))
                    .foregroundStyle(Color.appFg3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let onRetry, kind == .error {
                Button(action: onRetry) {
                    Text("common.retry")
                        .font(.appText(12, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.appAccentTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
        .appShadow(.card)
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
