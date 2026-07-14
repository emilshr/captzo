import AppKit
import CoreGraphics
import Foundation

@MainActor
@Observable
final class CaptureSessionState {
    var mode: CaptureMode = .selection
    var aspectRatio: AspectRatioOption = .oneToOne

    /// Selection rect in global AppKit coordinates (origin bottom-left).
    var selectionRect: CGRect = .zero
    var isDragging = false
    var isResizing = false

    /// Highlighted window under cursor (window mode).
    var hoveredWindowID: CGWindowID?
    var hoveredWindowFrame: CGRect = .zero
    var selectedWindowID: CGWindowID?

    /// Display mode: which display is selected.
    var selectedDisplayID: CGDirectDisplayID?

    var onModeChange: ((CaptureMode) -> Void)?
    var onAspectRatioChange: ((AspectRatioOption) -> Void)?
    var onRequestCapture: (() -> Void)?
    var onCancel: (() -> Void)?

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        onModeChange?(mode)
        hoveredWindowID = nil
        selectedWindowID = nil
        hoveredWindowFrame = .zero
    }

    func setAspectRatio(_ ratio: AspectRatioOption) {
        aspectRatio = ratio
        onAspectRatioChange?(ratio)
        if ratio.isLocked, selectionRect.width > 0 {
            selectionRect = Self.constrain(selectionRect, to: ratio)
        }
    }

    nonisolated static func constrain(_ rect: CGRect, to option: AspectRatioOption) -> CGRect {
        guard let target = option.ratio, target > 0 else { return rect }
        var result = rect
        let current = result.width / max(result.height, 1)
        if current > target {
            let newWidth = result.height * target
            result.origin.x += (result.width - newWidth) / 2
            result.size.width = newWidth
        } else {
            let newHeight = result.width / target
            result.origin.y += (result.height - newHeight) / 2
            result.size.height = newHeight
        }
        return result
    }

    nonisolated static func defaultSelection(on screen: NSScreen, aspect: AspectRatioOption) -> CGRect {
        let frame = screen.visibleFrame
        let side = min(frame.width, frame.height) * 0.4
        var size = CGSize(width: side, height: side)
        if let ratio = aspect.ratio {
            if ratio >= 1 {
                size = CGSize(width: side * ratio, height: side)
            } else {
                size = CGSize(width: side, height: side / ratio)
            }
            let maxW = frame.width * 0.8
            let maxH = frame.height * 0.8
            let scale = min(maxW / size.width, maxH / size.height, 1)
            size.width *= scale
            size.height *= scale
        }
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
