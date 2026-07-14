import Foundation
import Carbon.HIToolbox

enum AppPreferences {
    static let aspectRatioKey = "aspectRatio"
    static let sortOrderKey = "gallerySortOrder"
    static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    static let hotkeyModifiersKey = "hotkeyModifiers"
    static let openGalleryAfterCaptureKey = "openGalleryAfterCapture"
    static let hasConfiguredHotkeyKey = "hasConfiguredHotkey"

    /// Default: ⌘⇧6
    static let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_6)
    static let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    static var aspectRatio: AspectRatioOption {
        get {
            let raw = UserDefaults.standard.string(forKey: aspectRatioKey) ?? AspectRatioOption.oneToOne.rawValue
            return AspectRatioOption(rawValue: raw) ?? .oneToOne
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: aspectRatioKey)
        }
    }

    static var sortOrder: GallerySortOrder {
        get {
            let raw = UserDefaults.standard.string(forKey: sortOrderKey) ?? GallerySortOrder.newestFirst.rawValue
            return GallerySortOrder(rawValue: raw) ?? .newestFirst
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sortOrderKey)
        }
    }

    static var hotkeyKeyCode: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: hotkeyKeyCodeKey) == nil {
                return defaultHotkeyKeyCode
            }
            return UInt32(UserDefaults.standard.integer(forKey: hotkeyKeyCodeKey))
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: hotkeyKeyCodeKey)
        }
    }

    static var hotkeyModifiers: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: hotkeyModifiersKey) == nil {
                return defaultHotkeyModifiers
            }
            return UInt32(UserDefaults.standard.integer(forKey: hotkeyModifiersKey))
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: hotkeyModifiersKey)
        }
    }

    static var openGalleryAfterCapture: Bool {
        get { UserDefaults.standard.bool(forKey: openGalleryAfterCaptureKey) }
        set { UserDefaults.standard.set(newValue, forKey: openGalleryAfterCaptureKey) }
    }
}
