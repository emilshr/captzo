import Foundation
import SwiftUI

@MainActor
@Observable
final class LanguageStore {
    /// Process-wide accessor for AppKit hosts after `install(_:)`.
    private(set) static var current: LanguageStore?

    static func install(_ store: LanguageStore) {
        current = store
        store.syncL10nOverride()
    }

    /// Convenience for AppKit call sites that must not crash before install.
    static var shared: LanguageStore {
        if let current {
            return current
        }
        let store = LanguageStore()
        install(store)
        return store
    }

    var preference: AppLanguagePreference {
        didSet {
            guard preference != oldValue else { return }
            AppPreferences.uiLanguage = preference
            revision += 1
            syncL10nOverride()
            NotificationCenter.default.post(name: .scratioLanguageDidChange, object: nil)
        }
    }

    /// Bumped when preference changes so AppKit hosts can refresh root views.
    private(set) var revision: Int = 0

    init() {
        preference = AppPreferences.uiLanguage
        syncL10nOverride()
    }

    var resolvedLanguageCode: String {
        _ = revision
        return AppLanguageResolver.resolveLanguageCode(
            preference: preference,
            preferredLanguageCodes: AppLanguageResolver.preferredLanguageCodesFromSystem(),
            availableLocalizations: AppLanguageResolver.availableLocalizations()
        )
    }

    var resolvedLocale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    var layoutDirection: LayoutDirection {
        resolvedLocale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    /// Localized name of the resolved language, for the System picker row.
    var resolvedLanguageDisplayName: String {
        let code = resolvedLanguageCode
        return Locale.current.localizedString(forLanguageCode: code)
            ?? Locale(identifier: code).localizedString(forLanguageCode: code)
            ?? code
    }

    func setPreference(_ newValue: AppLanguagePreference) {
        preference = newValue
    }

    func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: resolvedLocale)
    }

    func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), locale: resolvedLocale)
    }

    fileprivate func syncL10nOverride() {
        L10n.localeOverride = resolvedLocale
    }
}

extension Notification.Name {
    static let scratioLanguageDidChange = Notification.Name("captzo.languageDidChange")
}
