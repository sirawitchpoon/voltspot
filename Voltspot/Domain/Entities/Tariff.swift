import Foundation

/// Tariff for a connector. Stored in THB minor units (satang) to avoid
/// floating-point money — divide by 100 when displaying.
struct Tariff: Codable, Sendable, Equatable {
    let pricePerKWhSatang: Int
    let sessionFeeSatang: Int

    var pricePerKWhBaht: Decimal {
        Decimal(pricePerKWhSatang) / 100
    }

    var sessionFeeBaht: Decimal {
        Decimal(sessionFeeSatang) / 100
    }
}
