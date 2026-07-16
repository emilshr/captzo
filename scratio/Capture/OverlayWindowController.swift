import AppKit
import SwiftUI

/// Borderless panel that can become key so Esc/Return reach the local monitor.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    static let toolbarSize = NSSize(width: 720, height: 72)

    private var overlayWindows: [NSWindow] = []
    private var toolbarWindow: NSWindow?
    private var interaction: CaptureOverlayInteraction?
    private let captureCursor = CaptureCursorController()

    private(set) var session = CaptureSessionState()

    func show(
        mode: CaptureMode,
        aspectRatio: AspectRatioOption,
        onModeChange: @escaping (CaptureMode) -> Void,
        onAspectRatioChange: @escaping (AspectRatioOption) -> Void,
        onCapture: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()

        session = CaptureSessionState()
        session.mode = mode
        session.aspectRatio = aspectRatio
        session.onModeChange = { [weak self] newMode in
            AppPreferences.captureMode = newMode
            onModeChange(newMode)
            self?.updateOverlayMousePassthrough()
            if newMode == .display {
                self?.session.selectedDisplayID = CaptureSessionState.displayID(at: NSEvent.mouseLocation)
            } else if newMode == .window {
                self?.interaction?.scheduleHoverUpdate(at: NSEvent.mouseLocation)
            }
            self?.updateCaptureCursor()
        }
        session.onAspectRatioChange = { newRatio in
            AppPreferences.aspectRatio = newRatio
            onAspectRatioChange(newRatio)
        }
        session.onRequestCapture = onCapture
        session.onCancel = onCancel

        restoreSelection(aspectRatio: aspectRatio)

        if mode == .display {
            session.selectedDisplayID = CaptureSessionState.displayID(at: NSEvent.mouseLocation)
        }

        for screen in NSScreen.screens {
            let window = makeOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.orderFront(nil)
        }

        toolbarWindow = makeToolbarWindow()
        toolbarWindow?.orderFront(nil)
        updateOverlayMousePassthrough()
        makeOverlayKey(under: NSEvent.mouseLocation)

        let interaction = CaptureOverlayInteraction(
            session: { [weak self] in self?.session ?? CaptureSessionState() },
            toolbarFrame: { [weak self] in self?.toolbarWindow?.frame },
            onMakeOverlayKey: { [weak self] location in self?.makeOverlayKey(under: location) },
            onCursorUpdate: { [weak self] in self?.updateCaptureCursor() },
            onCursorReset: { [weak self] in self?.captureCursor.reset() }
        )
        self.interaction = interaction
        interaction.install()
        if mode == .window {
            interaction.scheduleHoverUpdate(at: NSEvent.mouseLocation)
        }
        updateCaptureCursor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        interaction?.remove()
        interaction = nil
        captureCursor.reset()
        session.endSelectionInteraction(persist: false)
        for window in overlayWindows {
            window.delegate = nil
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        toolbarWindow?.delegate = nil
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
    }

    var overlayWindowNumbers: [Int] {
        overlayWindows.map(\.windowNumber) + (toolbarWindow.map { [$0.windowNumber] } ?? [])
    }

    private func restoreSelection(aspectRatio: AspectRatioOption) {
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let screens = CaptureSessionState.screenFrames()
        if let saved = AppPreferences.selectionRect,
           ScreenGeometry.isValidSelection(saved, onScreens: screens) {
            var restored = ScreenGeometry.clampRect(saved, toScreens: screens)
            if aspectRatio.isLocked {
                restored = CaptureSessionState.constrain(restored, to: aspectRatio)
                restored = ScreenGeometry.clampRect(restored, toScreens: screens)
            }
            session.selectionRect = restored
        } else {
            session.selectionRect = CaptureSessionState.defaultSelection(on: mouseScreen, aspect: aspectRatio)
        }
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = KeyablePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true

        let view = SelectionOverlayView(
            session: session,
            screen: screen,
            screenFrame: screen.frame
        )
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private func makeToolbarWindow() -> NSWindow {
        let size = Self.toolbarSize
        let frames = NSScreen.screens.map(\.frame)
        let origin: CGPoint
        if let saved = AppPreferences.toolbarOrigin,
           ScreenGeometry.isValidToolbarOrigin(saved, size: size, in: frames) {
            origin = saved
        } else {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
                ?? NSScreen.screens[0]
            origin = ScreenGeometry.defaultToolbarOrigin(on: screen.frame, size: size)
        }

        let window = KeyablePanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver + 1
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.hasShadow = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: CaptureToolbarView(session: session)
                .frame(width: size.width, height: size.height)
        )
        return window
    }

    private func updateOverlayMousePassthrough() {
        // All capture modes own mouse events so clicks never reach desktop apps.
        for window in overlayWindows {
            window.ignoresMouseEvents = false
        }
    }

    private func makeOverlayKey(under location: CGPoint) {
        if session.isSelectionInteracting { return }
        if let match = overlayWindows.first(where: { $0.frame.contains(location) }) {
            match.makeKeyAndOrderFront(nil)
        } else {
            overlayWindows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func updateCaptureCursor() {
        captureCursor.update(
            mode: session.mode,
            hoveredWindowID: session.hoveredWindowID,
            selectedWindowID: session.selectedWindowID,
            toolbarFrame: toolbarWindow?.frame
        )
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === toolbarWindow else { return }
        AppPreferences.toolbarOrigin = window.frame.origin
    }
}
