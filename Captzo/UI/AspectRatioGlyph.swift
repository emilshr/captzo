import AppKit
import SwiftUI

/// Solid outline box sized to match an aspect ratio for menu rows and badges.
struct AspectRatioGlyph: View {
    let option: AspectRatioOption
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        Canvas { context, canvasSize in
            let rect = Self.glyphRect(for: option, in: canvasSize)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            context.stroke(
                path,
                with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// AppKit image for macOS `Menu` rows, which often drop custom SwiftUI `Canvas` icons.
    static func nsImage(
        option: AspectRatioOption,
        size: CGFloat = 16,
        color: NSColor? = nil
    ) -> NSImage {
        let stroke = color ?? NSColor.labelColor
        let cacheKey = "\(option.rawValue)|\(Int(size * 100))|\(stroke.cacheKeyComponent)" as NSString
        if let cached = glyphImageCache.object(forKey: cacheKey) {
            return cached
        }

        let pixelSize = NSSize(width: size, height: size)
        let image = NSImage(size: pixelSize, flipped: false) { _ in
            stroke.withAlphaComponent(0.9).setStroke()

            let rect = glyphRect(for: option, in: CGSize(width: size, height: size))
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            return true
        }
        glyphImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    static func glyphRect(for option: AspectRatioOption, in canvasSize: CGSize) -> CGRect {
        let inset: CGFloat = 1.5
        let available = CGSize(
            width: canvasSize.width - inset * 2,
            height: canvasSize.height - inset * 2
        )

        guard let ratio = option.ratio else {
            // Freeform: irregular rounded rect
            return CGRect(
                x: inset + available.width * 0.1,
                y: inset + available.height * 0.15,
                width: available.width * 0.8,
                height: available.height * 0.7
            )
        }

        let fitted: CGSize
        if ratio >= 1 {
            let width = available.width
            let height = width / ratio
            if height <= available.height {
                fitted = CGSize(width: width, height: height)
            } else {
                fitted = CGSize(width: available.height * ratio, height: available.height)
            }
        } else {
            let height = available.height
            let width = height * ratio
            if width <= available.width {
                fitted = CGSize(width: width, height: height)
            } else {
                fitted = CGSize(width: available.width, height: available.width / ratio)
            }
        }

        return CGRect(
            x: inset + (available.width - fitted.width) / 2,
            y: inset + (available.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

private let glyphImageCache = NSCache<NSString, NSImage>()

private extension NSColor {
    var cacheKeyComponent: String {
        guard let rgb = usingColorSpace(.deviceRGB) ?? usingColorSpace(.sRGB) else {
            return "label"
        }
        return String(
            format: "%.3f-%.3f-%.3f-%.3f",
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent,
            rgb.alphaComponent
        )
    }
}

extension AspectRatioOption {
    var glyphNSColor: NSColor {
        let hex = AppPreferences.badgeColorHex(for: self) ?? defaultBadgeColorHex
        return NSColor(Color(hex: hex))
    }
}
