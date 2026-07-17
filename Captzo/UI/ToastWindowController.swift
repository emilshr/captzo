import AppKit
import SwiftUI

@MainActor
final class ToastWindowController {
    private var toastWindow: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(message: String, on screen: NSScreen?) {
        let targetScreen = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else { return }

        dismissTask?.cancel()

        let hostingView = NSHostingView(rootView: ToastView(message: message))
        hostingView.layoutSubtreeIfNeeded()
        let fitted = hostingView.fittingSize
        let contentSize = NSSize(
            width: max(180, min(360, fitted.width)),
            height: max(40, fitted.height)
        )

        let frame = toastFrame(for: contentSize, in: targetScreen)
        let window = toastWindow ?? makeWindow(frame: frame)
        window.setFrame(frame, display: true)
        window.contentView = hostingView
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 1
        }

        toastWindow = window
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.dismissAnimated()
        }
    }

    private func dismissAnimated() {
        guard let window = toastWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    private func makeWindow(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private func toastFrame(for size: NSSize, in screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let x = visible.midX - (size.width / 2)
        let y = visible.minY + 24
        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
