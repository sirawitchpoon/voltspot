import SwiftUI

struct PartnerDashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("partner.dashboard.greeting \(AppConfig.appName)")
                        .font(.title2)
                        .padding(.top)

                    StatCardGrid()

                    Text("partner.dashboard.activity")
                        .font(.headline)
                        .padding(.top)

                    ForEach(MockActivity.samples) { item in
                        ActivityRow(item: item)
                    }
                }
                .padding()
            }
            .navigationTitle("partner.tab.dashboard")
        }
    }
}

private struct StatCardGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "partner.stat.sessionsToday", value: "12")
            StatCard(title: "partner.stat.energyToday", value: "84.6 kWh")
            StatCard(title: "partner.stat.earningsMonth",
                     valueView: AnyView(ThaiBahtText(amount: 18250, bold: true)))
            StatCard(title: "partner.stat.activeStations", value: "3 / 4")
        }
    }
}

private struct StatCard: View {
    let title: LocalizedStringKey
    var value: String? = nil
    var valueView: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let valueView {
                valueView
                    .font(.title3)
            } else if let value {
                Text(value)
                    .font(.title3.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MockActivity: Identifiable {
    let id = UUID()
    let stationName: String
    let kwh: Double
    let earningsBaht: Decimal

    static let samples: [MockActivity] = [
        .init(stationName: "Asoke EV Hub", kwh: 22.4, earningsBaht: 168),
        .init(stationName: "Suphanburi Drone Field", kwh: 8.0, earningsBaht: 48),
        .init(stationName: "Korat AgriDepot Hybrid", kwh: 14.6, earningsBaht: 105),
    ]
}

private struct ActivityRow: View {
    let item: MockActivity

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.stationName).font(.subheadline)
                Text("\(item.kwh, specifier: "%.1f") kWh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ThaiBahtText(amount: item.earningsBaht, bold: true)
        }
        .padding(.vertical, 6)
    }
}
