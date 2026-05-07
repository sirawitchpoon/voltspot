import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class StationFinderViewModel {
    var stations: [Station] = []
    var selectedStation: Station?
    var cameraPosition: MapCameraPosition
    var isLoading: Bool = false
    var loadError: Error?

    /// Mirrors `LocationProvider.authorizationStatus` so the view can
    /// render a permission-denied banner without owning its own
    /// CoreLocation state.
    private(set) var locationAuthorization: CLAuthorizationStatus

    /// `true` once we've recentered the map on the user's first GPS
    /// fix. Subsequent fixes are tracked in `visibleRegion` but
    /// don't yank the camera around — users hate that.
    private var didRecenterOnFirstFix: Bool = false

    private(set) var visibleRegion: MKCoordinateRegion
    private let findNearby: FindNearbyStationsUseCase
    private let locationProvider: LocationProvider
    private var loadTask: Task<Void, Never>?

    init(locationProvider: LocationProvider = LocationProvider()) {
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: AppConfig.defaultMapCenterLat,
                longitude: AppConfig.defaultMapCenterLon
            ),
            span: MKCoordinateSpan(
                latitudeDelta: AppConfig.defaultMapSpanDegrees,
                longitudeDelta: AppConfig.defaultMapSpanDegrees
            )
        )
        self.visibleRegion = initialRegion
        self.cameraPosition = .region(initialRegion)
        self.findNearby = FindNearbyStationsUseCase(
            stationRepository: RealStationRepository()
        )
        self.locationProvider = locationProvider
        self.locationAuthorization = locationProvider.authorizationStatus

        // Wire callbacks. `[weak self]` so the provider doesn't keep
        // the view model alive after the view goes off-screen.
        self.locationProvider.onAuthorizationChanged = { [weak self] status in
            guard let self else { return }
            self.locationAuthorization = status
        }
        self.locationProvider.onLocationFix = { [weak self] coordinate in
            self?.handleLocationFix(coordinate)
        }
    }

    /// Initial load when the view first appears. Also kicks off the
    /// permission prompt the first time — denied users still get the
    /// Bangkok-default map + viewport-driven query, so the feature
    /// degrades gracefully.
    func loadInitialStations() async {
        locationProvider.requestWhenInUseIfNeeded()
        if locationProvider.isAuthorized {
            locationProvider.start()
        }
        await loadStations(in: visibleRegion)
    }

    /// Called from `.onDisappear` so we stop draining the GPS when
    /// the user is on a different tab.
    func stopTrackingLocation() {
        locationProvider.stop()
    }

    /// Called from `.onMapCameraChange(frequency: .onEnd)` after the user
    /// finishes a pan/zoom gesture. The Firestore query is debounced by
    /// ~250 ms so back-to-back pan-then-zoom doesn't fire two reads.
    func updateRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.loadStations(in: region)
        }
    }

    func zoomIn() {
        applyZoom(scale: 0.5)
    }

    func zoomOut() {
        applyZoom(scale: 2.0)
    }

    // MARK: - Private

    private func loadStations(in region: MKCoordinateRegion) async {
        let radiusKm = Self.radiusKm(for: region)
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            stations = try await findNearby(near: region.center, radiusKm: radiusKm)
        } catch is CancellationError {
            // Debounce cancelled the previous task — leave stations + error untouched.
            return
        } catch {
            stations = []
            loadError = error
        }
    }

    func retry() async {
        await loadStations(in: visibleRegion)
    }

    /// Handles a fresh GPS fix. On the very first fix we move the
    /// camera to the user's location with a friendly zoom — wider
    /// than "you are here" pin so they immediately see surrounding
    /// stations. After the first move we just track without
    /// hijacking pan/zoom intent.
    private func handleLocationFix(_ coordinate: CLLocationCoordinate2D) {
        guard !didRecenterOnFirstFix else { return }
        didRecenterOnFirstFix = true

        let firstFixSpan = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        let region = MKCoordinateRegion(center: coordinate, span: firstFixSpan)
        visibleRegion = region
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
        // Force a refetch around the new center — the .onMapCameraChange
        // hook fires too, but explicit refetch makes the round-trip
        // feel snappier (we don't wait for the camera-change debounce).
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadStations(in: region)
        }
    }

    private func applyZoom(scale: Double) {
        let span = visibleRegion.span
        let newLatDelta = (span.latitudeDelta * scale).clamped(to: 0.005...80)
        let newLngDelta = (span.longitudeDelta * scale).clamped(to: 0.005...80)
        let newRegion = MKCoordinateRegion(
            center: visibleRegion.center,
            span: MKCoordinateSpan(latitudeDelta: newLatDelta, longitudeDelta: newLngDelta)
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            cameraPosition = .region(newRegion)
        }
    }

    /// Approximate radius (km) for a Firestore query that covers the given
    /// region. Uses the larger of latitude / longitude half-spans, scaled by
    /// 1.2 to account for the geohash prefix slack, capped at 2000 km.
    private static func radiusKm(for region: MKCoordinateRegion) -> Double {
        let latKm = region.span.latitudeDelta * 111.0 / 2
        let lngKm = region.span.longitudeDelta * 111.0
            * cos(region.center.latitude * .pi / 180) / 2
        return min(max(latKm, lngKm) * 1.2, 2000)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
