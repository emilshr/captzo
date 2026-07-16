import AppKit

/// Screenshot-style cursor for Entire Screen and Window capture modes.
@MainActor
final class CaptureCursorController {
    private var isActive = false
    private lazy var screenshotCursor: NSCursor = Self.makeScreenshotCursor()

    /// Shows the capture cursor when appropriate for the current mode and pointer location.
    func update(
        mode: CaptureMode,
        hoveredWindowID: CGWindowID?,
        selectedWindowID: CGWindowID?,
        toolbarFrame: CGRect?
    ) {
        let location = NSEvent.mouseLocation
        if let toolbarFrame, toolbarFrame.contains(location) {
            reset()
            return
        }

        let shouldShow: Bool
        switch mode {
        case .display:
            shouldShow = true
        case .window:
            shouldShow = hoveredWindowID != nil || selectedWindowID != nil
        case .selection:
            shouldShow = false
        }

        if shouldShow {
            if !isActive {
                screenshotCursor.push()
                isActive = true
            } else {
                screenshotCursor.set()
            }
        } else {
            reset()
        }
    }

    func reset() {
        guard isActive else { return }
        NSCursor.pop()
        isActive = false
    }

    private static func makeScreenshotCursor() -> NSCursor {
        let paddedSize = NSSize(width: 28, height: 28)
        let symbolSize: CGFloat = 18
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        let base = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Capture")
            ?? NSImage(size: NSSize(width: symbolSize, height: symbolSize))
        let symbol = base.withSymbolConfiguration(config) ?? base

        let outline = tintedSymbol(symbol, color: .black, size: symbolSize)
        let fill = tintedSymbol(symbol, color: .white, size: symbolSize)

        let padded = NSImage(size: paddedSize, flipped: false) { bounds in
            let drawRect = NSRect(
                x: (bounds.width - symbolSize) / 2,
                y: (bounds.height - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            let outlineOffsets: [(CGFloat, CGFloat)] = [
                (-1, 0), (1, 0), (0, -1), (0, 1),
                (-1, -1), (-1, 1), (1, -1), (1, 1)
            ]
            for (offsetX, offsetY) in outlineOffsets {
                outline.draw(
                    in: drawRect.offsetBy(dx: offsetX, dy: offsetY),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            fill.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        padded.isTemplate = false

        return NSCursor(
            image: padded,
            hotSpot: NSPoint(x: paddedSize.width / 2, y: paddedSize.height / 2)
        )
    }

    private static func tintedSymbol(_ symbol: NSImage, color: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
