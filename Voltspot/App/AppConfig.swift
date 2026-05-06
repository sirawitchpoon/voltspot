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

    /// Base URL of the OCPP Gateway REST API.
    ///
    /// Debug builds default to `http://localhost:8080` so a developer
    /// can `go run ./cmd/gateway` on their Mac and see the iOS
    /// Simulator hit it. Release builds use the Cloud Run URL — this
    /// stays a placeholder until Phase B deploy lands; flipping the
    /// constant is the only change needed for prod.
    ///
    /// Override at runtime by passing `-VoltspotGatewayBaseURL <url>`
    /// as a launch argument (Xcode → Edit Scheme → Run → Arguments).
    /// Useful when testing the simulator against a Mac on the same
    /// network using its LAN IP.
    static var gatewayBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "VoltspotGatewayBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: defaultGatewayBaseURL)!
    }

    private static var defaultGatewayBaseURL: String {
        #if DEBUG
        return "http://localhost:8080"
        #else
        // TODO: replace with the Cloud Run URL once Phase B is deployed.
        // Format: https://<service>-<hash>-<region>.a.run.app
        return "https://ocpp-gateway-placeholder.a.run.app"
        #endif
    }
}
