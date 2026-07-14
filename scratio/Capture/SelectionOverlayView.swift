import AppKit
import SwiftUI

struct SelectionOverlayView: View {
    @Bindable var session: CaptureSessionState
    let screen: NSScreen
    /// Local frame of this overlay window (equals screen.frame).
    let screenFrame: CGRect

    @State private var dragStart: CGPoint?
    @State private var dragOriginRect: CGRect = .zero
    @State private var activeHandle: ResizeHandle?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Dim overlay with cutout for the active capture region
                DimCutoutShape(cutout: activeCutout)
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .allowsHitTesting(true)

                if session.mode == .selection, localSelectionRect.width > 1 {
                    selectionChrome
                }

                if session.mode == .window, session.hoveredWindowFrame != .zero {
                    windowHighlight
                }

                if session.mode == .display {
                    displayHighlight
                }
            }
            .contentShape(Rectangle())
            .gesture(selectionGesture)
            .onTapGesture(count: 1, perform: handleTap)
        }
        .ignoresSafeArea()
    }

    private var localSelectionRect: CGRect {
        toLocal(session.selectionRect)
    }

    private var activeCutout: CGRect {
        switch session.mode {
        case .selection:
            return localSelectionRect
        case .window:
            return session.hoveredWindowFrame == .zero ? .zero : toLocal(session.hoveredWindowFrame)
        case .display:
            // Full-screen cutout (no dim) for the active display overlay
            return CGRect(origin: .zero, size: CGSize(width: screenFrame.width, height: screenFrame.height))
        }
    }

    private var selectionChrome: some View {
        ZStack {
            // Marching ants style dashed border
            Rectangle()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(Color.white)
                .frame(width: localSelectionRect.width, height: localSelectionRect.height)
                .position(x: localSelectionRect.midX, y: localSelectionRect.midY)

            Rectangle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                .frame(width: localSelectionRect.width, height: localSelectionRect.height)
                .position(x: localSelectionRect.midX, y: localSelectionRect.midY)

            // Grid crosshairs (subtle, like native)
            Path { path in
                let r = localSelectionRect
                path.move(to: CGPoint(x: r.minX + r.width / 3, y: r.minY))
                path.addLine(to: CGPoint(x: r.minX + r.width / 3, y: r.maxY))
                path.move(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.minY))
                path.addLine(to: CGPoint(x: r.minX + 2 * r.width / 3, y: r.maxY))
                path.move(to: CGPoint(x: r.minX, y: r.minY + r.height / 3))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height / 3))
                path.move(to: CGPoint(x: r.minX, y: r.minY + 2 * r.height / 3))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * r.height / 3))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

            ForEach(ResizeHandle.allCases) { handle in
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(radius: 1)
                    .position(handle.point(in: localSelectionRect))
            }

            Text(sizeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .position(
                    x: localSelectionRect.midX,
                    y: max(14, localSelectionRect.minY - 16)
                )
        }
        .allowsHitTesting(false)
    }

    private var windowHighlight: some View {
        let local = toLocal(session.hoveredWindowFrame)
        return Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.08))
            .frame(width: local.width, height: local.height)
            .position(x: local.midX, y: local.midY)
            .allowsHitTesting(false)
    }

    private var displayHighlight: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 4)
            .padding(2)
            .allowsHitTesting(false)
    }

    private var sizeLabel: String {
        let w = Int(session.selectionRect.width.rounded())
        let h = Int(session.selectionRect.height.rounded())
        return "\(w) × \(h)"
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                guard session.mode == .selection else { return }
                if dragStart == nil {
                    dragStart = value.startLocation
                    let handle = hitHandle(at: value.startLocation)
                    activeHandle = handle
                    if handle != nil {
                        session.isResizing = true
                        dragOriginRect = localSelectionRect
                    } else if localSelectionRect.contains(value.startLocation) {
                        session.isDragging = true
                        dragOriginRect = localSelectionRect
                    } else {
                        // Start new selection from drag
                        session.isDragging = false
                        session.isResizing = false
                        dragOriginRect = CGRect(origin: value.startLocation, size: .zero)
                    }
                }

                if let handle = activeHandle {
                    var rect = resize(dragOriginRect, handle: handle, to: value.location)
                    if session.aspectRatio.isLocked {
                        rect = constrainLocal(rect, to: session.aspectRatio)
                    }
                    session.selectionRect = toGlobal(rect)
                } else if session.isDragging {
                    let dx = value.location.x - (dragStart?.x ?? 0)
                    let dy = value.location.y - (dragStart?.y ?? 0)
                    var moved = dragOriginRect.offsetBy(dx: dx, dy: dy)
                    moved = clampToScreen(moved)
                    session.selectionRect = toGlobal(moved)
                } else if let start = dragStart {
                    var rect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                    if session.aspectRatio.isLocked {
                        rect = constrainLocalFromCorner(rect, start: start, current: value.location)
                    }
                    session.selectionRect = toGlobal(clampToScreen(rect))
                }
            }
            .onEnded { _ in
                dragStart = nil
                activeHandle = nil
                session.isDragging = false
                session.isResizing = false
            }
    }

    private func handleTap() {
        switch session.mode {
        case .selection:
            // Tap outside selection does not capture; camera / Enter does.
            break
        case .window:
            if session.hoveredWindowID != nil {
                session.selectedWindowID = session.hoveredWindowID
                // Selecting a window does not capture — camera button does.
            }
        case .display:
            if let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                session.selectedDisplayID = CGDirectDisplayID(did.uint32Value)
            }
        }
    }

    // MARK: - Coordinates

    /// Convert global AppKit rect to local SwiftUI coords (top-left origin within this screen window).
    private func toLocal(_ global: CGRect) -> CGRect {
        // Overlay window is placed at screen.frame; SwiftUI Y grows downward.
        let x = global.origin.x - screenFrame.origin.x
        let yFromBottom = global.origin.y - screenFrame.origin.y
        let y = screenFrame.height - yFromBottom - global.height
        return CGRect(x: x, y: y, width: global.width, height: global.height)
    }

    private func toGlobal(_ local: CGRect) -> CGRect {
        let x = local.origin.x + screenFrame.origin.x
        let yFromBottom = screenFrame.height - local.origin.y - local.height
        let y = yFromBottom + screenFrame.origin.y
        return CGRect(x: x, y: y, width: local.width, height: local.height)
    }

    private func clampToScreen(_ local: CGRect) -> CGRect {
        var r = local
        r.size.width = max(20, min(r.width, screenFrame.width))
        r.size.height = max(20, min(r.height, screenFrame.height))
        r.origin.x = min(max(0, r.origin.x), screenFrame.width - r.width)
        r.origin.y = min(max(0, r.origin.y), screenFrame.height - r.height)
        return r
    }

    private func constrainLocal(_ rect: CGRect, to option: AspectRatioOption) -> CGRect {
        guard let ratio = option.ratio else { return rect }
        var r = rect
        let newHeight = r.width / ratio
        r.origin.y += (r.height - newHeight) / 2
        r.size.height = newHeight
        return clampToScreen(r)
    }

    private func constrainLocalFromCorner(
        _ rect: CGRect,
        start: CGPoint,
        current: CGPoint
    ) -> CGRect {
        guard let ratio = session.aspectRatio.ratio else { return rect }
        let width = abs(current.x - start.x)
        let heightFromWidth = width / ratio
        let signX: CGFloat = current.x >= start.x ? 1 : -1
        let signY: CGFloat = current.y >= start.y ? 1 : -1
        return CGRect(
            x: signX > 0 ? start.x : start.x - width,
            y: signY > 0 ? start.y : start.y - heightFromWidth,
            width: width,
            height: heightFromWidth
        )
    }

    private func hitHandle(at point: CGPoint) -> ResizeHandle? {
        let r = localSelectionRect
        for handle in ResizeHandle.allCases {
            let p = handle.point(in: r)
            if hypot(p.x - point.x, p.y - point.y) < 12 {
                return handle
            }
        }
        return nil
    }

    private func resize(_ origin: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var r = origin
        switch handle {
        case .topLeft:
            r.size.width = r.maxX - point.x
            r.size.height = r.maxY - point.y
            r.origin = point
        case .topRight:
            r.size.width = point.x - r.minX
            r.size.height = r.maxY - point.y
            r.origin.y = point.y
        case .bottomLeft:
            r.size.width = r.maxX - point.x
            r.size.height = point.y - r.minY
            r.origin.x = point.x
        case .bottomRight:
            r.size.width = point.x - r.minX
            r.size.height = point.y - r.minY
        case .top:
            r.size.height = r.maxY - point.y
            r.origin.y = point.y
        case .bottom:
            r.size.height = point.y - r.minY
        case .left:
            r.size.width = r.maxX - point.x
            r.origin.x = point.x
        case .right:
            r.size.width = point.x - r.minX
        }
        if r.width < 20 { r.size.width = 20 }
        if r.height < 20 { r.size.height = 20 }
        return clampToScreen(r)
    }
}

private struct DimCutoutShape: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if cutout.width > 1, cutout.height > 1 {
            path.addRect(cutout)
        }
        return path
    }
}

enum ResizeHandle: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
