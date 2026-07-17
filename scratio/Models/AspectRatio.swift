import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum AspectRatioOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneToOne = "1:1"
    case sixteenToNine = "16:9"
    case nineToSixteen = "9:16"
    case fourToThree = "4:3"
    case threeToFour = "3:4"
    case threeToTwo = "3:2"
    case twoToThree = "2:3"
    case freeform = "Freeform"

    /// Legacy raw value used before the Freeform rename.
    static let legacyIndependentRawValue = "Independent"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Width / height. `nil` means freeform (unlocked).
    var ratio: CGFloat? {
        switch self {
        case .oneToOne: return 1
        case .sixteenToNine: return 16 / 9
        case .nineToSixteen: return 9 / 16
        case .fourToThree: return 4 / 3
        case .threeToFour: return 3 / 4
        case .threeToTwo: return 3 / 2
        case .twoToThree: return 2 / 3
        case .freeform: return nil
        }
    }

    var isLocked: Bool { ratio != nil }

    /// Default badge color hex (RGB, no alpha).
    var defaultBadgeColorHex: String {
        switch self {
        case .oneToOne: return "5B8DEF"
        case .sixteenToNine: return "3DDC97"
        case .nineToSixteen: return "F4A261"
        case .fourToThree: return "9B5DE5"
        case .threeToFour: return "EF476F"
        case .threeToTwo: return "00BBF9"
        case .twoToThree: return "FEE440"
        case .freeform: return "8E9AAF"
        }
    }

    var badgeColor: Color {
        Color(hex: AppPreferences.badgeColorHex(for: self) ?? defaultBadgeColorHex)
    }

    /// Decodes persisted strings, including the legacy `"Independent"` value.
    static func fromPersisted(_ raw: String?) -> AspectRatioOption? {
        guard let raw else { return nil }
        if let option = AspectRatioOption(rawValue: raw) {
            return option
        }
        if raw == legacyIndependentRawValue {
            return .freeform
        }
        return nil
    }
}

enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case selection
    case window
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: return "Selection"
        case .window: return "Window"
        case .display: return "Entire Screen"
        }
    }

    var systemImage: String {
        switch self {
        case .selection: return "rectangle.dashed"
        case .window: return "macwindow"
        case .display: return "display"
        }
    }
}

enum GallerySortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let red: Double
        let green: Double
        let blue: Double
        switch cleaned.count {
        case 6:
            red = Double((int >> 16) & 0xFF) / 255
            green = Double((int >> 8) & 0xFF) / 255
            blue = Double(int & 0xFF) / 255
        default:
            red = 0.5
            green = 0.5
            blue = 0.5
        }
        self.init(red: red, green: green, blue: blue)
    }

    func hexString() -> String? {
        #if os(macOS)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor.usingColorSpace(.sRGB) else {
            return nil
        }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(
            format: "%02X%02X%02X",
            max(0, min(255, red)),
            max(0, min(255, green)),
            max(0, min(255, blue))
        )
        #else
        return nil
        #endif
    }
}
