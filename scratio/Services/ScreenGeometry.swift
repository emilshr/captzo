import CoreGraphics
import Foundation

/// Pure geometry helpers for multi-display capture (testable without AppKit screens).
enum ScreenGeometry {
    static let minimumSelectionSide: CGFloat = 20

    /// Union of all screen frames (virtual desktop in AppKit coordinates).
    static func virtualDesktopUnion(of frames: [CGRect]) -> CGRect {
        guard let first = frames.first else { return .zero }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Clamps a rect to stay fully inside `bounds`, enforcing a minimum size.
    static func clampRect(_ rect: CGRect, to bounds: CGRect, minSize: CGFloat = minimumSelectionSide) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return rect }

        var r = rect
        r.size.width = max(minSize, min(r.width, bounds.width))
        r.size.height = max(minSize, min(r.height, bounds.height))
        r.origin.x = min(max(bounds.minX, r.origin.x), bounds.maxX - r.size.width)
        r.origin.y = min(max(bounds.minY, r.origin.y), bounds.maxY - r.size.height)
        return r
    }

    /// Clamps a rect to real screen frames so it cannot sit in inter-display gaps.
    /// Allows spanning multiple screens when the center remains on a screen.
    static func clampRect(_ rect: CGRect, toScreens screens: [CGRect], minSize: CGFloat = minimumSelectionSide) -> CGRect {
        guard !screens.isEmpty else { return rect }
        let union = virtualDesktopUnion(of: screens)
        var r = clampRect(rect, to: union, minSize: minSize)
        let center = CGPoint(x: r.midX, y: r.midY)
        if screens.contains(where: { $0.contains(center) }) {
            return r
        }
        // Center fell into a gap — snap onto the nearest screen.
        let nearest = screens.min { a, b in
            distanceSquared(center, to: a) < distanceSquared(center, to: b)
        }!
        return clampRect(r, to: nearest, minSize: minSize)
    }

    /// Whether a selection rect is usable for restore (intersects a real screen and large enough).
    static func isValidSelection(_ rect: CGRect, in desktop: CGRect) -> Bool {
        guard rect.width >= minimumSelectionSide, rect.height >= minimumSelectionSide else { return false }
        guard desktop.width > 0, desktop.height > 0 else { return false }
        return rect.intersects(desktop)
    }

    static func isValidSelection(_ rect: CGRect, onScreens screens: [CGRect]) -> Bool {
        guard rect.width >= minimumSelectionSide, rect.height >= minimumSelectionSide else { return false }
        return screens.contains { $0.intersects(rect) }
    }

    /// Converts AppKit global rect (origin bottom-left) to Quartz/SCK space.
    static func convertToCaptureSpace(_ appKitRect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        let flippedY = primaryMaxY - appKitRect.origin.y - appKitRect.height
        return CGRect(
            x: appKitRect.origin.x,
            y: flippedY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    /// Converts SCK/CG window frame (top-left) to AppKit global (bottom-left).
    static func convertSCWindowFrameToAppKit(_ frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryMaxY - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// Finds which screen frame contains a point (AppKit coords).
    static func screenFrameIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Whether a toolbar origin is still on a known screen (top-left of toolbar frame intersects any screen).
    static func isValidToolbarOrigin(_ origin: CGPoint, size: CGSize, in frames: [CGRect]) -> Bool {
        let rect = CGRect(origin: origin, size: size)
        return frames.contains { $0.intersects(rect) }
    }

    /// Default toolbar origin: bottom-centered on the given screen frame.
    static func defaultToolbarOrigin(on screenFrame: CGRect, size: CGSize, bottomPadding: CGFloat = 36) -> CGPoint {
        CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + bottomPadding
        )
    }

    /// Pixel buffer size for window capture from filter content metrics.
    static func capturePixelSize(contentRect: CGRect, pointPixelScale: CGFloat) -> (width: Int, height: Int)? {
        guard contentRect.width > 0, contentRect.height > 0, pointPixelScale > 0 else { return nil }
        let width = max(Int((contentRect.width * pointPixelScale).rounded()), 1)
        let height = max(Int((contentRect.height * pointPixelScale).rounded()), 1)
        return (width, height)
    }

    /// Samples a coarse grid and returns mean luminance in 0...1 (sRGB-ish average of RGB).
    static func meanLuminance(of cgImage: CGImage, sampleStride: Int = 16) -> CGFloat? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let bitsPerPixel = cgImage.bitsPerPixel
        let bitsPerComponent = cgImage.bitsPerComponent
        guard bitsPerComponent == 8, bitsPerPixel >= 24 else { return nil }

        let bytesPerPixel = bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let alphaInfo = cgImage.alphaInfo
        let stride = max(sampleStride, 1)

        var total: CGFloat = 0
        var count = 0
        var y = 0
        while y < cgImage.height {
            var x = 0
            while x < cgImage.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r: CGFloat
                let g: CGFloat
                let b: CGFloat
                switch alphaInfo {
                case .premultipliedFirst, .first, .noneSkipFirst:
                    // ARGB / XRGB
                    r = CGFloat(bytes[offset + 1]) / 255
                    g = CGFloat(bytes[offset + 2]) / 255
                    b = CGFloat(bytes[offset + 3]) / 255
                default:
                    // RGBA / BGRA — ScreenCaptureKit BGRA lands here often as byte order B,G,R,A
                    if cgImage.bitmapInfo.contains(.byteOrder32Little) {
                        b = CGFloat(bytes[offset + 0]) / 255
                        g = CGFloat(bytes[offset + 1]) / 255
                        r = CGFloat(bytes[offset + 2]) / 255
                    } else {
                        r = CGFloat(bytes[offset + 0]) / 255
                        g = CGFloat(bytes[offset + 1]) / 255
                        b = CGFloat(bytes[offset + 2]) / 255
                    }
                }
                total += (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
                count += 1
                x += stride
            }
            y += stride
        }
        guard count > 0 else { return nil }
        return total / CGFloat(count)
    }

    /// True when the image looks like a failed blank capture.
    static func isNearlyBlank(_ cgImage: CGImage, luminanceThreshold: CGFloat = 0.02) -> Bool {
        guard let luminance = meanLuminance(of: cgImage) else { return false }
        return luminance < luminanceThreshold
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }
        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
    }
}
