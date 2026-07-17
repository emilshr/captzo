import Foundation
import SwiftUI

/// Persisted UI language choice. `.system` follows the user’s preferred languages.
enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case german = "de"
    case french = "fr"
    case portugueseBrazil = "pt-BR"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"

    var id: String { rawValue }

    /// Language codes for which the app ships translations.
    static let bundledLanguageCodes: [String] = [
        "en", "es", "zh-Hans", "ja", "de", "fr", "pt-BR", "ko", "ar", "hi"
    ]

    /// Explicit language cases shown in the Settings picker (excludes `.system`).
    static var explicitLanguages: [AppLanguagePreference] {
        allCases.filter { $0 != .system }
    }

    /// Native-script label for the picker (not localized).
    var pickerLabel: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .japanese: return "日本語"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .portugueseBrazil: return "Português"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        }
    }

    /// BCP-47 code used for locale resolution when this is an explicit choice.
    var languageCode: String? {
        switch self {
        case .system: return nil
        default: return rawValue
        }
    }
}

/// Pure resolver used by `LanguageStore` and tests.
enum AppLanguageResolver: Sendable {
    /// Returns a BCP-47 language code present in `availableLocalizations` (e.g. `"en"`, `"zh-Hans"`).
    static func resolveLanguageCode(
        preference: AppLanguagePreference,
        preferredLanguageCodes: [String],
        availableLocalizations: [String]
    ) -> String {
        let available = normalizedAvailability(availableLocalizations)

        if let code = preference.languageCode {
            if let match = match(preferred: code, available: available) {
                return match
            }
            return fallbackEnglish(in: available)
        }

        for preferred in preferredLanguageCodes {
            if let match = match(preferred: preferred, available: available) {
                return match
            }
        }
        return fallbackEnglish(in: available)
    }

    static func preferredLanguageCodesFromSystem() -> [String] {
        if #available(macOS 26.0, *) {
            return Locale.preferredLocales.map(\.identifier)
        }
        return Locale.preferredLanguages
    }

    static func availableLocalizations(from bundle: Bundle = .main) -> [String] {
        bundle.localizations
    }

    private static func normalizedAvailability(_ localizations: [String]) -> Set<String> {
        Set(
            localizations
                .map { normalizeKey($0) }
                .filter { $0 != "base" && !$0.isEmpty }
        )
    }

    private static func fallbackEnglish(in available: Set<String>) -> String {
        if let english = match(preferred: "en", available: available) {
            return english
        }
        if let first = available.sorted().first {
            return canonicalize(first, available: available)
        }
        return "en"
    }

    private static func match(preferred: String, available: Set<String>) -> String? {
        let lowered = normalizeKey(preferred)
        if available.contains(lowered) {
            return canonicalize(lowered, available: available)
        }

        // zh-Hans / pt-BR style: try language + script/region progressively.
        let parts = lowered.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            let languageScript = parts.prefix(2).joined(separator: "-")
            if available.contains(languageScript) {
                return canonicalize(languageScript, available: available)
            }
        }

        let languageOnly = Locale(identifier: preferred).language.languageCode?.identifier.lowercased()
            ?? parts.first
            ?? lowered
        if available.contains(languageOnly) {
            return canonicalize(languageOnly, available: available)
        }

        for candidate in available {
            if lowered.hasPrefix(candidate + "-") || lowered.hasPrefix(candidate + "_") {
                return canonicalize(candidate, available: available)
            }
        }
        return nil
    }

    private static func canonicalize(_ code: String, available: Set<String>) -> String {
        if let bundled = AppLanguagePreference.bundledLanguageCodes.first(where: {
            normalizeKey($0) == normalizeKey(code)
        }) {
            return bundled
        }
        return code
    }

    private static func normalizeKey(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

/// Looks up strings for the current in-app language (works outside SwiftUI environment).
enum L10n {
    /// Updated by `LanguageStore` when preference changes so AppKit paths stay in sync.
    nonisolated(unsafe) static var localeOverride: Locale?

    nonisolated static var currentLocale: Locale {
        if let localeOverride {
            return localeOverride
        }
        let preference = AppPreferences.uiLanguage
        let code = AppLanguageResolver.resolveLanguageCode(
            preference: preference,
            preferredLanguageCodes: AppLanguageResolver.preferredLanguageCodesFromSystem(),
            availableLocalizations: AppLanguageResolver.availableLocalizations()
        )
        return Locale(identifier: code)
    }

    nonisolated static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: currentLocale)
    }

    nonisolated static func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), locale: currentLocale)
    }
}

extension View {
    /// Injects language store + locale + layout direction for in-app language switching.
    func captzoLocalized(_ store: LanguageStore) -> some View {
        environment(store)
            .environment(\.locale, store.resolvedLocale)
            .environment(\.layoutDirection, store.layoutDirection)
    }
}
