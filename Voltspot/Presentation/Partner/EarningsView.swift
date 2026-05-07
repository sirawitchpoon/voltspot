import SwiftUI

struct EarningsView: View {
    @State private var viewModel = EarningsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        bigStatCard
                        breakdownRow
                        dailyChartCard
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.appText(12))
                                .foregroundStyle(Color.appDanger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.lg)
                        }
                        payoutsSection
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("partner.tab.earnings")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    // MARK: - Sub-views

    private var bigStatCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text("partner.earnings.thisMonth")
                    .font(.appText(12, weight: .medium))
            }
            .foregroundStyle(Color.appFg3)

            ThaiBahtText(amount: bahtAmount(viewModel.netSatang), bold: true)
                .font(.appMono(38, weight: .semibold))
                .foregroundStyle(Color.appFg)

            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("\(viewModel.monthSessions.count) sessions")
                    .font(.appMono(12, weight: .semibold))
            }
            .foregroundStyle(Color.appAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.xl)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
    }

    private var breakdownRow: some View {
        HStack(spacing: AppSpacing.sm) {
            breakdownItem(
                label: "partner.earnings.gross",
                amount: bahtAmount(viewModel.grossSatang),
                accent: false
            )
            breakdownItem(
                label: "partner.earnings.commission",
                amount: -bahtAmount(viewModel.commissionSatang),
                accent: false,
                danger: true
            )
            breakdownItem(
                label: "partner.earnings.net",
                amount: bahtAmount(viewModel.netSatang),
                accent: true
            )
        }
    }

    private func breakdownItem(label: LocalizedStringKey, amount: Decimal, accent: Bool, danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.appText(10, weight: .medium))
                .foregroundStyle(Color.appFg3)
            ThaiBahtText(amount: amount, bold: true)
                .font(.appMono(13, weight: .semibold))
                .foregroundStyle(accent ? Color.appAccent : (danger ? Color.appDanger : Color.appFg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(
            (accent ? Color.appAccentTint : Color.appSurface),
            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
        )
    }

    /// Daily revenue bar chart over the trailing 30 days. Bars scale
    /// against whichever bucket has the largest revenue so the chart
    /// stays useful even on small absolute numbers.
    private var dailyChartCard: some View {
        let bins = viewModel.dailyRevenueSatang
        // bins[0] is today, bins[29] is 29 days ago. Reverse for L→R
        // chronological reading.
        let chronological = Array(bins.reversed())
        let peak = max(chronological.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("partner.earnings.daily")
                .font(.appText(13, weight: .semibold))
                .foregroundStyle(Color.appFg)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(chronological.enumerated()), id: \.offset) { idx, satang in
                    let isLast = idx == chronological.count - 1
                    let normalized = Double(satang) / Double(peak)
                    let h: CGFloat = max(2, CGFloat(normalized) * 80)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isLast ? Color.appAccent : Color.appAccentTint)
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
        .padding(AppSpacing.lg)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
    }

    /// Payouts come from a payout pipeline that doesn't exist yet —
    /// keep the card as a forward-looking empty state so partners
    /// still see it on the screen and we don't have to redesign once
    /// the bank-payout integration ships.
    private var payoutsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("partner.earnings.payouts")
                .font(.appText(13, weight: .semibold))
                .foregroundStyle(Color.appFg3)
                .textCase(.uppercase)
                .padding(.leading, AppSpacing.sm)
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "wallet.bifold")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.appFg3)
                Text("partner.earnings.payouts.empty")
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
        }
    }

    private func bahtAmount(_ satang: Int) -> Decimal {
        Decimal(satang) / 100
    }
}
