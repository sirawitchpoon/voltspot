import SwiftUI

struct EarningsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("partner.earnings.thisMonth") {
                    HStack {
                        Text("partner.earnings.gross")
                        Spacer()
                        ThaiBahtText(amount: 18250, bold: true)
                    }
                    HStack {
                        Text("partner.earnings.commission")
                        Spacer()
                        ThaiBahtText(amount: 2737)
                    }
                    HStack {
                        Text("partner.earnings.net")
                        Spacer()
                        ThaiBahtText(amount: 15513, bold: true)
                    }
                }

                Section("partner.earnings.payouts") {
                    Text("partner.earnings.empty")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("partner.tab.earnings")
        }
    }
}
