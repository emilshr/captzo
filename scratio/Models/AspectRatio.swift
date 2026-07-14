import Foundation
import CoreGraphics

enum AspectRatioOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneToOne = "1:1"
    case sixteenToNine = "16:9"
    case nineToSixteen = "9:16"
    case fourToThree = "4:3"
    case threeToFour = "3:4"
    case threeToTwo = "3:2"
    case twoToThree = "2:3"
    case independent = "Independent"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Width / height. `nil` means freeform (independent).
    var ratio: CGFloat? {
        switch self {
        case .oneToOne: return 1
        case .sixteenToNine: return 16 / 9
        case .nineToSixteen: return 9 / 16
        case .fourToThree: return 4 / 3
        case .threeToFour: return 3 / 4
        case .threeToTwo: return 3 / 2
        case .twoToThree: return 2 / 3
        case .independent: return nil
        }
    }

    var isLocked: Bool { ratio != nil }
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
