import SwiftUI

struct PartnerDashboardView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("partner.dashboard.greeting \(AppConfig.appName)")
                                .font(.appText(22, weight: .bold))
                                .foregroundStyle(Color.appFg)
                            Text("partner.dashboard.subtitle")
                                .font(.appText(13))
                                .foregroundStyle(Color.appFg3)
                        }
                        .padding(.top, AppSpacing.sm)

                        StatTileGrid()

                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("partner.dashboard.activity")
                                .font(.appText(17, weight: .semibold))
                                .foregroundStyle(Color.appFg)
                            VStack(spacing: 0) {
                                ForEach(MockActivity.samples) { item in
                                    ActivityRow(item: item)
                                    if item.id != MockActivity.samples.last?.id {
                                        Rectangle()
                                            .fill(Color.appRule)
                                            .frame(height: 0.5)
                                            .padding(.leading, AppSpacing.lg)
                                    }
                                }
                            }
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                    .stroke(Color.appRule, lineWidth: 1)
                            )
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("partner.tab.dashboard")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct StatTileGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
            StatTile(label: "partner.stat.sessionsToday", value: "12", icon: "bolt.fill")
            StatTile(label: "partner.stat.energyToday", value: "84.6", unit: "kWh", icon: "leaf.fill")
            StatTile(label: "partner.stat.earningsMonth", value: CurrencyFormatter.thb.string(from: 18250), icon: "banknote.fill", accent: true)
            StatTile(label: "partner.stat.activeStations", value: "3 / 4", icon: "building.2.fill")
        }
    }
}

private struct MockActivity: Identifiable {
    let id = UUID()
    let stationName: String
    let kwh: Double
    let earningsBaht: Decimal
    let kind: ConnectorKind

    static let samples: [MockActivity] = [
        .init(stationName: "Asoke EV Hub", kwh: 22.4, earningsBaht: 168, kind: .ev),
        .init(stationName: "Suphanburi Drone Field", kwh: 8.0, earningsBaht: 48, kind: .drone),
        .init(stationName: "Korat AgriDepot Hybrid", kwh: 14.6, earningsBaht: 105, kind: .ev),
    ]
}

private struct ActivityRow: View {
    let item: MockActivity

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(item.kind.chipBackground)
                Image(systemName: item.kind == .ev ? "bolt.fill" : "airplane")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.kind.tintColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.stationName)
                    .font(.appText(14, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text("\(item.kwh, specifier: "%.1f") kWh")
                    .font(.appMono(11, weight: .medium))
                    .foregroundStyle(Color.appFg3)
            }
            Spacer()
            ThaiBahtText(amount: item.earningsBaht, bold: true)
                .font(.appMono(15, weight: .semibold))
                .foregroundStyle(Color.appFg)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}
