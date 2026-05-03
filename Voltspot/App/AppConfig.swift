import Foundation

/// Single source of truth for brand and locale-related constants.
///
/// To rebrand the app, change `appName` here. No other file references the
/// brand string directly — every UI label resolves through this constant.
enum AppConfig {
    static let appName: String = "Voltspot"
    static let supportEmail: String = "support@example.com"

    static let defaultLanguage: String = "th"
    static let supportedLanguages: [String] = ["th", "en"]

    static let currencyCode: String = "THB"
    static let currencyLocaleIdentifier: String = "th_TH"

    static let defaultMapCenterLat: Double = 13.7563
    static let defaultMapCenterLon: Double = 100.5018
    static let defaultMapSpanDegrees: Double = 8.0

    static let minimumPasswordLength: Int = 8
}
