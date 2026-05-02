import SwiftUI

/// Convenience wrapper that formats a Decimal amount as THB using the
/// shared formatter, so callers don't pass strings around.
struct ThaiBahtText: View {
    let amount: Decimal
    var bold: Bool = false

    var body: some View {
        let text = Text(CurrencyFormatter.thb.string(from: amount))
        if bold {
            text.bold()
        } else {
            text
        }
    }
}
