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
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Capture")
            ?? NSImage(size: NSSize(width: 24, height: 24))
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        image.isTemplate = true

        let paddedSize = NSSize(width: 28, height: 28)
        let padded = NSImage(size: paddedSize, flipped: false) { _ in
            let origin = NSPoint(
                x: (paddedSize.width - image.size.width) / 2,
                y: (paddedSize.height - image.size.height) / 2
            )
            image.draw(
                in: NSRect(origin: origin, size: image.size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        padded.isTemplate = true

        return NSCursor(
            image: padded,
            hotSpot: NSPoint(x: paddedSize.width / 2, y: paddedSize.height / 2)
        )
    }
}
