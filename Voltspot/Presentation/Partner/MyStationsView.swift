import CoreLocation
import SwiftUI

struct MyStationsView: View {
    @State private var stations: [Station] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                Group {
                    if stations.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: AppSpacing.md) {
                                ForEach(stations) { station in
                                    PartnerStationCard(station: station)
                                }
                            }
                            .padding(AppSpacing.lg)
                        }
                    }
                }
            }
            .navigationTitle("partner.tab.stations")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                stations = (try? await RealStationRepository().nearbyStations(
                    near: .init(
                        latitude: AppConfig.defaultMapCenterLat,
                        longitude: AppConfig.defaultMapCenterLon
                    ),
                    radiusKm: 1500
                )) ?? []
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface2)
                    .frame(width: 120, height: 120)
                Image(systemName: "building.2")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.appFg3)
            }
            VStack(spacing: AppSpacing.sm) {
                Text("partner.stations.empty.title")
                    .font(.appText(18, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text("partner.stations.empty.description")
                    .font(.appText(13))
                    .foregroundStyle(Color.appFg3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppSpacing.xl)
    }
}

private struct PartnerStationCard: View {
    let station: Station

    private var liveCount: Int { station.connectors.filter { $0.status == .available }.count }
    private var totalCount: Int { station.connectors.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.appAccentTint)
                    Image(systemName: station.supportsDrones ? "airplane" : "building.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.appText(15, weight: .semibold))
                        .foregroundStyle(Color.appFg)
                    Text(station.address)
                        .font(.appText(12))
                        .foregroundStyle(Color.appFg3)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(
                    style: liveCount > 0 ? .available : .offline,
                    label: "\(liveCount) live"
                )
            }

            HStack(spacing: AppSpacing.sm) {
                miniStat(label: "partner.stations.connectors", value: "\(totalCount)")
                miniStat(label: "partner.stations.energyToday", value: "32.4 kWh")
                miniStat(label: "partner.stations.revenueToday", value: CurrencyFormatter.thb.string(from: 540))
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
    }

    private func miniStat(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.appText(10, weight: .medium))
                .foregroundStyle(Color.appFg3)
            Text(value)
                .font(.appMono(13, weight: .semibold))
                .foregroundStyle(Color.appFg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }
}
