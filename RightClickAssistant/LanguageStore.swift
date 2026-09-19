import AppKit
import Combine
import Foundation

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            let defaults = SharedPreferences.defaults
            defaults.set(selection.rawValue, forKey: AppLanguage.preferenceKey)
            defaults.synchronize()
            // Match macOS per-app language preferences for localized bundle names
            // on the next launch. The app's own UI switches without a relaunch.
            UserDefaults.standard.set([selection.rawValue], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            for window in NSApp?.windows ?? [] where AppLanguage.allCases.map(\.appName).contains(window.title) {
                window.title = selection.appName
            }
        }
    }

    var locale: Locale { Locale(identifier: selection.rawValue) }
    private init() { selection = .current }
}
