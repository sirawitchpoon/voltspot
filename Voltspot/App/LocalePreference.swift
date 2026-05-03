import Foundation
import Observation

/// App-wide language toggle. Backed by `LanguagePreferenceStore` for
/// persistence; pushed into the SwiftUI environment from
/// `VoltspotApp.body` as `\.locale` so every `Text` and
/// `LocalizedStringKey` re-renders when the user flips it.
///
/// Setting `UserDefaults["AppleLanguages"]` alongside the in-memory
/// flip widens coverage to non-SwiftUI lookups (`String(localized:)`
/// callers, `Bundle.main.localizedString`) — those don't observe
/// `\.locale` directly. Already-rendered strings update on the next
/// view re-render; system-level UI (alerts, share sheets) flips on
/// next presentation.
@MainActor
@Observable
final class LocalePreference {
    private let store: LanguagePreferenceStore
    private(set) var current: String

    init(store: LanguagePreferenceStore = LanguagePreferenceStore()) {
        self.store = store
        if let saved = store.loadLanguage(),
           AppConfig.supportedLanguages.contains(saved) {
            self.current = saved
        } else {
            self.current = Self.systemDefault()
        }
        // Keep AppleLanguages in sync with the saved choice on launch
        // so non-view localization lookups match the SwiftUI environment
        // from frame 0, not after the first toggle.
        Self.applyAppleLanguages(self.current)
    }

    var locale: Locale { Locale(identifier: current) }

    func toggle() {
        let next = current == "th" ? "en" : "th"
        set(next)
    }

    func set(_ code: String) {
        guard AppConfig.supportedLanguages.contains(code), code != current else { return }
        current = code
        store.saveLanguage(code)
        Self.applyAppleLanguages(code)
    }

    private static func applyAppleLanguages(_ code: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }

    private static func systemDefault() -> String {
        let preferred = Locale.preferredLanguages.first ?? AppConfig.defaultLanguage
        let lang = String(preferred.prefix(2))
        return AppConfig.supportedLanguages.contains(lang) ? lang : AppConfig.defaultLanguage
    }
}
