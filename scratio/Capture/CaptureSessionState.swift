import AppKit
import CoreGraphics
import Foundation

enum SelectionDragKind: Equatable {
    case none
    case move
    case resize(ResizeHandle)
    case create
}

@MainActor
@Observable
final class CaptureSessionState {
    var mode: CaptureMode = .selection
    var aspectRatio: AspectRatioOption = .oneToOne

    /// Selection rect in global AppKit coordinates (origin bottom-left).
    var selectionRect: CGRect = .zero
    var isDragging = false
    var isResizing = false

    /// Cross-screen selection interaction (AppKit global coords).
    var selectionDragKind: SelectionDragKind = .none
    var selectionDragStart: CGPoint = .zero
    var selectionDragOriginRect: CGRect = .zero

    /// Highlighted window under cursor (window mode).
    var hoveredWindowID: CGWindowID?
    var hoveredWindowFrame: CGRect = .zero
    var selectedWindowID: CGWindowID?

    /// Display mode: which display is selected / hovered.
    var selectedDisplayID: CGDirectDisplayID?

    var onModeChange: ((CaptureMode) -> Void)?
    var onAspectRatioChange: ((AspectRatioOption) -> Void)?
    var onRequestCapture: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelectionCommitted: (() -> Void)?

    var isSelectionInteracting: Bool {
        selectionDragKind != .none || isDragging || isResizing
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        onModeChange?(mode)
        hoveredWindowID = nil
        selectedWindowID = nil
        hoveredWindowFrame = .zero
        selectedDisplayID = nil
        endSelectionInteraction(persist: false)
        if mode == .display {
            selectedDisplayID = Self.displayID(at: NSEvent.mouseLocation)
        }
    }

    func setAspectRatio(_ ratio: AspectRatioOption) {
        aspectRatio = ratio
        onAspectRatioChange?(ratio)
        if ratio.isLocked, selectionRect.width > 0 {
            let constrained = Self.constrain(selectionRect, to: ratio)
            selectionRect = Self.clampSelection(constrained)
        }
        persistSelection()
    }

    func persistSelection() {
        guard selectionRect.width >= ScreenGeometry.minimumSelectionSide,
              selectionRect.height >= ScreenGeometry.minimumSelectionSide else { return }
        AppPreferences.selectionRect = selectionRect
        onSelectionCommitted?()
    }

    func beginSelectionInteraction(at location: CGPoint) {
        guard mode == .selection else { return }
        selectionDragStart = location
        selectionDragOriginRect = selectionRect

        if let handle = hitHandle(at: location) {
            selectionDragKind = .resize(handle)
            isResizing = true
            isDragging = false
        } else if selectionRect.insetBy(dx: -2, dy: -2).contains(location) {
            selectionDragKind = .move
            isDragging = true
            isResizing = false
        } else {
            selectionDragKind = .create
            isDragging = false
            isResizing = false
            selectionRect = CGRect(origin: location, size: .zero)
        }
    }

    func updateSelectionInteraction(at location: CGPoint) {
        guard mode == .selection else { return }
        switch selectionDragKind {
        case .none:
            return
        case .move:
            let dx = location.x - selectionDragStart.x
            let dy = location.y - selectionDragStart.y
            let moved = selectionDragOriginRect.offsetBy(dx: dx, dy: dy)
            selectionRect = Self.clampSelection(moved)
        case .resize(let handle):
            var rect = resize(selectionDragOriginRect, handle: handle, to: location)
            if aspectRatio.isLocked {
                rect = Self.constrain(rect, to: aspectRatio)
            }
            selectionRect = Self.clampSelection(rect)
        case .create:
            var rect = CGRect(
                x: min(selectionDragStart.x, location.x),
                y: min(selectionDragStart.y, location.y),
                width: abs(location.x - selectionDragStart.x),
                height: abs(location.y - selectionDragStart.y)
            )
            if let ratio = aspectRatio.ratio {
                let width = abs(location.x - selectionDragStart.x)
                let heightFromWidth = width / ratio
                let signX: CGFloat = location.x >= selectionDragStart.x ? 1 : -1
                let signY: CGFloat = location.y >= selectionDragStart.y ? 1 : -1
                rect = CGRect(
                    x: signX > 0 ? selectionDragStart.x : selectionDragStart.x - width,
                    y: signY > 0 ? selectionDragStart.y : selectionDragStart.y - heightFromWidth,
                    width: width,
                    height: heightFromWidth
                )
            }
            selectionRect = Self.clampSelection(rect)
        }
    }

    func endSelectionInteraction(persist: Bool = true) {
        selectionDragKind = .none
        isDragging = false
        isResizing = false
        if persist {
            persistSelection()
        }
    }

    func hitHandle(at point: CGPoint) -> ResizeHandle? {
        for handle in ResizeHandle.allCases {
            let p = handle.appKitPoint(in: selectionRect)
            if hypot(p.x - point.x, p.y - point.y) < 12 {
                return handle
            }
        }
        return nil
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

    @MainActor
    static func screenFrames() -> [CGRect] {
        NSScreen.screens.map(\.frame)
    }

    @MainActor
    static func virtualDesktopBounds() -> CGRect {
        ScreenGeometry.virtualDesktopUnion(of: screenFrames())
    }

    @MainActor
    static func clampSelection(_ rect: CGRect) -> CGRect {
        ScreenGeometry.clampRect(rect, toScreens: screenFrames())
    }

    @MainActor
    static func displayID(at location: CGPoint) -> CGDirectDisplayID {
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        if let num = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(num.uint32Value)
        }
        return CGMainDisplayID()
    }

    @MainActor
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(num.uint32Value)
    }

    /// Resize in AppKit global space (Y grows upward).
    private func resize(_ origin: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var r = origin
        switch handle {
        case .topLeft:
            r.size.width = r.maxX - point.x
            r.size.height = point.y - r.minY
            r.origin.x = point.x
        case .topRight:
            r.size.width = point.x - r.minX
            r.size.height = point.y - r.minY
        case .bottomLeft:
            r.size.width = r.maxX - point.x
            r.size.height = r.maxY - point.y
            r.origin = point
        case .bottomRight:
            r.size.width = point.x - r.minX
            r.size.height = r.maxY - point.y
            r.origin.y = point.y
        case .top:
            r.size.height = point.y - r.minY
        case .bottom:
            r.size.height = r.maxY - point.y
            r.origin.y = point.y
        case .left:
            r.size.width = r.maxX - point.x
            r.origin.x = point.x
        case .right:
            r.size.width = point.x - r.minX
        }
        if r.width < ScreenGeometry.minimumSelectionSide {
            r.size.width = ScreenGeometry.minimumSelectionSide
        }
        if r.height < ScreenGeometry.minimumSelectionSide {
            r.size.height = ScreenGeometry.minimumSelectionSide
        }
        return r
    }
}
