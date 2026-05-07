import SwiftUI

struct PartnerDashboardView: View {
    @State private var viewModel = PartnerDashboardViewModel()

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

                        StatTileGrid(
                            sessionsToday: viewModel.sessionsTodayCount,
                            energyTodayKWh: viewModel.energyTodayKWh,
                            monthGrossSatang: viewModel.monthGrossSatang,
                            activeStationsLabel: viewModel.activeStationsLabel
                        )

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.appText(12))
                                .foregroundStyle(Color.appDanger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.md)
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("partner.dashboard.activity")
                                .font(.appText(17, weight: .semibold))
                                .foregroundStyle(Color.appFg)
                            ActivityListCard(
                                activities: viewModel.recentActivity,
                                stationNameProvider: viewModel.stationName(for:)
                            )
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("partner.tab.dashboard")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }
}

private struct StatTileGrid: View {
    let sessionsToday: Int
    let energyTodayKWh: Double
    let monthGrossSatang: Int
    let activeStationsLabel: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
            StatTile(label: "partner.stat.sessionsToday", value: "\(sessionsToday)", icon: "bolt.fill")
            StatTile(label: "partner.stat.energyToday", value: String(format: "%.1f", energyTodayKWh), unit: "kWh", icon: "leaf.fill")
            StatTile(
                label: "partner.stat.earningsMonth",
                value: CurrencyFormatter.thb.string(from: Decimal(monthGrossSatang) / 100),
                icon: "banknote.fill",
                accent: true
            )
            StatTile(label: "partner.stat.activeStations", value: activeStationsLabel, icon: "building.2.fill")
        }
    }
}

/// Empty / loaded list of recent partner sessions.
private struct ActivityListCard: View {
    let activities: [ChargingSession]
    let stationNameProvider: (String) -> String

    var body: some View {
        if activities.isEmpty {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "bolt.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.appFg3)
                Text("partner.dashboard.activity.empty")
                    .font(.appText(12))
                    .foregroundStyle(Color.appFg3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(Color.appRule, lineWidth: 1)
            )
        } else {
            VStack(spacing: 0) {
                ForEach(activities) { item in
                    ActivityRow(
                        stationName: stationNameProvider(item.stationId),
                        kwh: item.energyKWh,
                        earningsBaht: Decimal(item.costSatang) / 100,
                        kind: .ev
                    )
                    if item.id != activities.last?.id {
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
}

private struct ActivityRow: View {
    let stationName: String
    let kwh: Double
    let earningsBaht: Decimal
    let kind: ConnectorKind

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(kind.chipBackground)
                Image(systemName: kind == .ev ? "bolt.fill" : "airplane")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kind.tintColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(stationName)
                    .font(.appText(14, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text("\(kwh, specifier: "%.1f") kWh")
                    .font(.appMono(11, weight: .medium))
                    .foregroundStyle(Color.appFg3)
            }
            Spacer()
            ThaiBahtText(amount: earningsBaht, bold: true)
                .font(.appMono(15, weight: .semibold))
                .foregroundStyle(Color.appFg)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}
