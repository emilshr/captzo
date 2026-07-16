import AppKit
import ScreenCaptureKit
import SwiftUI

/// Borderless panel that can become key so Esc/Return reach the local monitor.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    static let toolbarSize = NSSize(width: 520, height: 72)

    private var overlayWindows: [NSWindow] = []
    private var toolbarWindow: NSWindow?
    private var keyMonitor: Any?
    private var mouseMovedLocal: Any?
    private var mouseMovedGlobal: Any?
    private var mouseDownLocal: Any?
    private var mouseDraggedLocal: Any?
    private var mouseUpLocal: Any?
    private var mouseDraggedGlobal: Any?
    private var mouseUpGlobal: Any?
    private var hoverTask: Task<Void, Never>?
    private var hoverGeneration: UInt64 = 0
    private var cachedWindows: [SCWindow] = []
    private var windowsCacheTime: Date = .distantPast
    private let windowsCacheTTL: TimeInterval = 0.25

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
                self?.scheduleHoverUpdate(at: NSEvent.mouseLocation)
            }
        }
        session.onAspectRatioChange = { newRatio in
            AppPreferences.aspectRatio = newRatio
            onAspectRatioChange(newRatio)
        }
        session.onRequestCapture = onCapture
        session.onCancel = onCancel

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

        installMonitors()
        if mode == .window {
            scheduleHoverUpdate(at: NSEvent.mouseLocation)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        hoverTask?.cancel()
        hoverTask = nil
        cachedWindows = []
        windowsCacheTime = .distantPast
        removeMonitors()
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
        // Selection and window need hit-testing; display stays click-through (hover only).
        let passThrough = session.mode == .display
        for window in overlayWindows {
            window.ignoresMouseEvents = passThrough
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

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.session.onCancel?()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad enter
                self.session.onRequestCapture?()
                return nil
            }
            return event
        }

        mouseMovedLocal = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
        mouseMovedGlobal = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }

        mouseDownLocal = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if self.handleMouseDown() {
                return nil
            }
            return event
        }
        mouseDraggedLocal = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleSelectionMouseDragged()
            return event
        }
        mouseUpLocal = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleSelectionMouseUp()
            return event
        }
        mouseDraggedGlobal = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in
                self?.handleSelectionMouseDragged()
            }
        }
        mouseUpGlobal = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleSelectionMouseUp()
            }
        }
    }

    private func removeMonitors() {
        let monitors: [Any?] = [
            keyMonitor, mouseMovedLocal, mouseMovedGlobal,
            mouseDownLocal, mouseDraggedLocal, mouseUpLocal,
            mouseDraggedGlobal, mouseUpGlobal,
        ]
        for monitor in monitors {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        keyMonitor = nil
        mouseMovedLocal = nil
        mouseMovedGlobal = nil
        mouseDownLocal = nil
        mouseDraggedLocal = nil
        mouseUpLocal = nil
        mouseDraggedGlobal = nil
        mouseUpGlobal = nil
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        if !session.isSelectionInteracting {
            makeOverlayKey(under: location)
        }

        switch session.mode {
        case .window:
            scheduleHoverUpdate(at: location)
        case .display:
            session.selectedDisplayID = CaptureSessionState.displayID(at: location)
        case .selection:
            break
        }
    }

    /// Returns `true` when the event should be swallowed.
    private func handleMouseDown() -> Bool {
        let location = NSEvent.mouseLocation
        // Ignore clicks on the toolbar panel.
        if let toolbar = toolbarWindow, toolbar.frame.contains(location) {
            return false
        }

        switch session.mode {
        case .selection:
            session.beginSelectionInteraction(at: location)
            return false
        case .window:
            let windowID = session.hoveredWindowID ?? session.selectedWindowID
            guard windowID != nil else { return true }
            session.onRequestCapture?()
            return true
        case .display:
            return false
        }
    }

    private func handleSelectionMouseDragged() {
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.updateSelectionInteraction(at: NSEvent.mouseLocation)
    }

    private func handleSelectionMouseUp() {
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.endSelectionInteraction(persist: true)
    }

    private func scheduleHoverUpdate(at location: NSPoint) {
        hoverTask?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, generation == hoverGeneration else { return }
            await updateHoveredWindow(at: location, generation: generation)
        }
    }

    private func updateHoveredWindow(at location: NSPoint, generation: UInt64) async {
        do {
            let windows = try await fetchWindowsForHover()
            guard !Task.isCancelled, generation == hoverGeneration else { return }

            let location = NSEvent.mouseLocation
            let hit = ScreenshotCaptureService.windowAt(point: location, in: windows)
            guard generation == hoverGeneration else { return }

            session.hoveredWindowID = hit?.windowID
            session.selectedWindowID = hit?.windowID
            if let hit {
                session.hoveredWindowFrame = ScreenshotCaptureService.convertSCWindowFrameToAppKit(hit.frame)
            } else {
                session.hoveredWindowFrame = .zero
            }
        } catch {
            // Ignore hover failures during permission prompts
        }
    }

    private func fetchWindowsForHover() async throws -> [SCWindow] {
        let now = Date()
        if now.timeIntervalSince(windowsCacheTime) < windowsCacheTTL, !cachedWindows.isEmpty {
            return cachedWindows
        }
        let windows = try await ScreenshotCaptureService.fetchWindows()
        cachedWindows = windows
        windowsCacheTime = now
        return windows
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === toolbarWindow else { return }
        AppPreferences.toolbarOrigin = window.frame.origin
    }
}
