import SwiftUI

struct EarningsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        bigStatCard
                        breakdownRow
                        dailyChartCard
                        payoutsSection
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("partner.tab.earnings")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var bigStatCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text("partner.earnings.thisMonth")
                    .font(.appText(12, weight: .medium))
            }
            .foregroundStyle(Color.appFg3)

            ThaiBahtText(amount: 16425, bold: true)
                .font(.appMono(38, weight: .semibold))
                .foregroundStyle(Color.appFg)

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                Text("+12.4%")
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
            breakdownItem(label: "partner.earnings.gross", amount: 18250, accent: false)
            breakdownItem(label: "partner.earnings.commission", amount: -2737, accent: false, danger: true)
            breakdownItem(label: "partner.earnings.net", amount: 15513, accent: true)
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

    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("partner.earnings.daily")
                .font(.appText(13, weight: .semibold))
                .foregroundStyle(Color.appFg)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<30, id: \.self) { i in
                    let isLast = i == 29
                    let h = CGFloat.random(in: 18...80)
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

    private var payoutsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("partner.earnings.payouts")
                .font(.appText(13, weight: .semibold))
                .foregroundStyle(Color.appFg3)
                .textCase(.uppercase)
                .padding(.leading, AppSpacing.sm)
            VStack(spacing: 0) {
                ForEach(MockPayout.samples) { item in
                    PayoutRow(item: item)
                    if item.id != MockPayout.samples.last?.id {
                        Rectangle().fill(Color.appRule).frame(height: 0.5)
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

private struct MockPayout: Identifiable {
    let id = UUID()
    let label: String
    let date: String
    let amount: Decimal
    let isPaid: Bool

    static let samples: [MockPayout] = [
        .init(label: "โอนเข้าบัญชี SCB", date: "30 เม.ย. 2569", amount: 14820, isPaid: true),
        .init(label: "โอนเข้าบัญชี SCB", date: "31 มี.ค. 2569", amount: 11540, isPaid: true),
        .init(label: "รอบวันที่ 31 พ.ค.", date: "31 พ.ค. 2569", amount: 15513, isPaid: false),
    ]
}

private struct PayoutRow: View {
    let item: MockPayout

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(item.isPaid ? Color.appAccentTint : Color.appGold.opacity(0.18))
                Image(systemName: "wallet.bifold")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isPaid ? Color.appAccent : Color.appGold)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.appText(14, weight: .medium))
                    .foregroundStyle(Color.appFg)
                Text(item.date)
                    .font(.appMono(11))
                    .foregroundStyle(Color.appFg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ThaiBahtText(amount: item.amount, bold: true)
                    .font(.appMono(14, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text(item.isPaid ? "PAID" : "PENDING")
                    .font(.appMono(9, weight: .semibold))
                    .foregroundStyle(item.isPaid ? Color.appAccent : Color.appGold)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}
