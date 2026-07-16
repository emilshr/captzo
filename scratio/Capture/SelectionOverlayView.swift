import AppKit
import SwiftUI

struct SelectionOverlayView: View {
    @Bindable var session: CaptureSessionState
    let screen: NSScreen
    /// Local frame of this overlay window (equals screen.frame).
    let screenFrame: CGRect

    private var screenDisplayID: CGDirectDisplayID? {
        CaptureSessionState.displayID(for: screen)
    }

    private var isSelectedDisplay: Bool {
        guard let screenDisplayID else { return false }
        return session.selectedDisplayID == screenDisplayID
    }

    var body: some View {
        ZStack {
                // Dim overlay with cutout for the active capture region.
                // Hit-testing stays enabled in selection mode so the NSWindow
                // receives mouse-down and local monitors can drive cross-screen drags.
                DimCutoutShape(cutout: activeCutout)
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                if session.mode == .selection, localSelectionRect.width > 1 {
                    selectionChrome
                }

                if session.mode == .window,
                   session.hoveredWindowFrame != .zero,
                   session.hoveredWindowFrame.intersects(screenFrame) {
                    windowHighlight
                }

                if session.mode == .display, isSelectedDisplay {
                    displayHighlight
                }
            }
            .contentShape(Rectangle())
            .allowsHitTesting(session.mode != .display)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            guard session.hoveredWindowFrame != .zero,
                  session.hoveredWindowFrame.intersects(screenFrame) else {
                return .zero
            }
            return toLocal(session.hoveredWindowFrame)
        case .display:
            // Clear cutout only on the hovered/selected display; others stay dimmed.
            return isSelectedDisplay
                ? CGRect(origin: .zero, size: CGSize(width: screenFrame.width, height: screenFrame.height))
                : .zero
        }
    }

    private var selectionChrome: some View {
        ZStack {
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

    /// Convert global AppKit rect to local SwiftUI coords (top-left origin within this screen window).
    private func toLocal(_ global: CGRect) -> CGRect {
        let x = global.origin.x - screenFrame.origin.x
        let yFromBottom = global.origin.y - screenFrame.origin.y
        let y = screenFrame.height - yFromBottom - global.height
        return CGRect(x: x, y: y, width: global.width, height: global.height)
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

    /// Point in SwiftUI local coords (Y grows downward) for a local selection rect.
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

    /// Point in AppKit global coords (Y grows upward) for a global selection rect.
    func appKitPoint(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }
}
