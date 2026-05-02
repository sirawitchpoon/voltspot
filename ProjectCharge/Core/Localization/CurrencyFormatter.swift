import Foundation

/// Shared THB formatter. Uses the locale specified in `AppConfig` so the
/// currency symbol (฿) and grouping match Thai conventions when the user
/// hasn't set a system locale we know about.
struct CurrencyFormatter: Sendable {
    static let thb = CurrencyFormatter()

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = AppConfig.currencyCode
        f.locale = Locale(identifier: AppConfig.currencyLocaleIdentifier)
        return f
    }()

    func string(from amount: Decimal) -> String {
        formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
