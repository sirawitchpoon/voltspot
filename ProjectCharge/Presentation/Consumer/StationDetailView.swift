import SwiftUI

struct StationDetailView: View {
    let station: Station

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(station.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("station.tariff.perKWh")
                        Spacer()
                        ThaiBahtText(amount: station.tariff.pricePerKWhBaht, bold: true)
                    }
                    if station.tariff.sessionFeeSatang > 0 {
                        HStack {
                            Text("station.tariff.sessionFee")
                            Spacer()
                            ThaiBahtText(amount: station.tariff.sessionFeeBaht)
                        }
                    }

                    Divider()

                    Text("station.connectors")
                        .font(.headline)
                    ForEach(station.connectors) { connector in
                        ConnectorRow(connector: connector)
                    }

                    Spacer()

                    Button {
                        // Stub: a real implementation would talk to the
                        // backend Central System and start a session.
                    } label: {
                        Text("station.startSession")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!station.connectors.contains { $0.status == .available })
                }
                .padding()
            }
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ConnectorRow: View {
    let connector: Connector

    var body: some View {
        HStack {
            Image(systemName: connector.kind == .drone ? "airplane" : "bolt.fill")
            VStack(alignment: .leading) {
                Text(connector.standard.rawValue)
                    .font(.subheadline)
                Text("\(Int(connector.powerKW)) kW")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(LocalizedStringKey("connector.status.\(connector.status.rawValue)"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
    }

    private var statusColor: Color {
        switch connector.status {
        case .available: return .green
        case .occupied: return .orange
        case .faulted: return .red
        case .unavailable: return .gray
        }
    }
}
