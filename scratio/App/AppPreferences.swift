import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum AppPreferences {
    /// Injectable for tests; defaults to `.standard`.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static let aspectRatioKey = "aspectRatio"
    static let sortOrderKey = "gallerySortOrder"
    static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    static let hotkeyModifiersKey = "hotkeyModifiers"
    static let openGalleryAfterCaptureKey = "openGalleryAfterCapture"
    static let hasConfiguredHotkeyKey = "hasConfiguredHotkey"
    static let captureModeKey = "captureMode"
    static let selectionRectKey = "selectionRect"
    static let toolbarOriginKey = "toolbarOrigin"
    static let clipboardToastMessageKey = "clipboardToastMessage"
    static let aspectRatioBadgeColorsKey = "aspectRatioBadgeColors"
    static let uiLanguageKey = "uiLanguage"

    /// Default: ⌘⇧6
    static let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_6)
    static let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    /// English source key; display via `L10n.tr` when the user has not customized the toast.
    static let defaultClipboardToastMessage = "Copied to clipboard"

    static var aspectRatio: AspectRatioOption {
        get {
            let raw = defaults.string(forKey: aspectRatioKey) ?? AspectRatioOption.oneToOne.rawValue
            return AspectRatioOption.fromPersisted(raw) ?? .oneToOne
        }
        set {
            defaults.set(newValue.rawValue, forKey: aspectRatioKey)
        }
    }

    static var captureMode: CaptureMode {
        get {
            let raw = defaults.string(forKey: captureModeKey) ?? CaptureMode.selection.rawValue
            return CaptureMode(rawValue: raw) ?? .selection
        }
        set {
            defaults.set(newValue.rawValue, forKey: captureModeKey)
        }
    }

    static var sortOrder: GallerySortOrder {
        get {
            let raw = defaults.string(forKey: sortOrderKey) ?? GallerySortOrder.newestFirst.rawValue
            return GallerySortOrder(rawValue: raw) ?? .newestFirst
        }
        set {
            defaults.set(newValue.rawValue, forKey: sortOrderKey)
        }
    }

    static var hotkeyKeyCode: UInt32 {
        get {
            if defaults.object(forKey: hotkeyKeyCodeKey) == nil {
                return defaultHotkeyKeyCode
            }
            return UInt32(defaults.integer(forKey: hotkeyKeyCodeKey))
        }
        set {
            defaults.set(Int(newValue), forKey: hotkeyKeyCodeKey)
        }
    }

    static var hotkeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: hotkeyModifiersKey) == nil {
                return defaultHotkeyModifiers
            }
            return UInt32(defaults.integer(forKey: hotkeyModifiersKey))
        }
        set {
            defaults.set(Int(newValue), forKey: hotkeyModifiersKey)
        }
    }

    static var openGalleryAfterCapture: Bool {
        get { defaults.bool(forKey: openGalleryAfterCaptureKey) }
        set { defaults.set(newValue, forKey: openGalleryAfterCaptureKey) }
    }

    static var clipboardToastMessage: String {
        get {
            let saved = defaults.string(forKey: clipboardToastMessageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved, !saved.isEmpty, saved != defaultClipboardToastMessage {
                return saved
            }
            return ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultClipboardToastMessage {
                defaults.removeObject(forKey: clipboardToastMessageKey)
            } else {
                defaults.set(trimmed, forKey: clipboardToastMessageKey)
            }
        }
    }

    /// `true` when the toast still uses the built-in default (should be localized at display time).
    static var usesDefaultClipboardToastMessage: Bool {
        let saved = defaults.string(forKey: clipboardToastMessageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved, !saved.isEmpty else { return true }
        return saved == defaultClipboardToastMessage
    }

    static var uiLanguage: AppLanguagePreference {
        get {
            let raw = defaults.string(forKey: uiLanguageKey) ?? AppLanguagePreference.system.rawValue
            return AppLanguagePreference(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: uiLanguageKey)
        }
    }

    static var selectionRect: CGRect? {
        get {
            guard let dict = defaults.dictionary(forKey: selectionRectKey) else { return nil }
            guard
                let x = cgFloat(dict["x"]),
                let y = cgFloat(dict["y"]),
                let w = cgFloat(dict["width"]),
                let h = cgFloat(dict["height"])
            else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            guard let rect = newValue else {
                defaults.removeObject(forKey: selectionRectKey)
                return
            }
            defaults.set(
                [
                    "x": Double(rect.origin.x),
                    "y": Double(rect.origin.y),
                    "width": Double(rect.size.width),
                    "height": Double(rect.size.height),
                ],
                forKey: selectionRectKey
            )
        }
    }

    static var toolbarOrigin: CGPoint? {
        get {
            guard let dict = defaults.dictionary(forKey: toolbarOriginKey) else { return nil }
            guard let x = cgFloat(dict["x"]), let y = cgFloat(dict["y"]) else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let point = newValue else {
                defaults.removeObject(forKey: toolbarOriginKey)
                return
            }
            defaults.set(
                ["x": Double(point.x), "y": Double(point.y)],
                forKey: toolbarOriginKey
            )
        }
    }

    static func badgeColorHex(for option: AspectRatioOption) -> String? {
        let overrides = badgeColorOverrides()
        if let hex = overrides[option.rawValue] {
            return hex
        }
        // Migrate legacy Independent badge color key for Freeform.
        if option == .freeform {
            return overrides[AspectRatioOption.legacyIndependentRawValue]
        }
        return nil
    }

    static func setBadgeColorHex(_ hex: String?, for option: AspectRatioOption) {
        var overrides = badgeColorOverrides()
        if option == .freeform {
            overrides.removeValue(forKey: AspectRatioOption.legacyIndependentRawValue)
        }
        if let hex, !hex.isEmpty {
            overrides[option.rawValue] = hex.uppercased()
        } else {
            overrides.removeValue(forKey: option.rawValue)
        }
        defaults.set(overrides, forKey: aspectRatioBadgeColorsKey)
    }

    static func resetBadgeColors() {
        defaults.removeObject(forKey: aspectRatioBadgeColorsKey)
    }

    private static func badgeColorOverrides() -> [String: String] {
        defaults.dictionary(forKey: aspectRatioBadgeColorsKey) as? [String: String] ?? [:]
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let float = value as? CGFloat {
            return float
        }
        return nil
    }
}
