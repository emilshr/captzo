import AppKit
import SwiftUI

/// Attaches a native AppKit `toolTip` so hover tips work on floating nonactivating panels
/// where SwiftUI `.help()` often does not appear.
struct AppKitTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipHostView {
        let view = TooltipHostView()
        view.tooltipText = text
        return view
    }

    func updateNSView(_ nsView: TooltipHostView, context: Context) {
        nsView.tooltipText = text
    }
}

/// Transparent view that registers an AppKit tooltip over its bounds without stealing clicks.
final class TooltipHostView: NSView {
    var tooltipText: String = "" {
        didSet {
            toolTip = tooltipText.isEmpty ? nil : tooltipText
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks reach the SwiftUI control underneath.
        nil
    }
}

extension View {
    func appKitTooltip(_ text: String) -> some View {
        background {
            AppKitTooltip(text: text)
        }
    }
}
