import AppKit
import ScreenCaptureKit
import SwiftUI

/// Borderless panel that can become key so Esc/Return reach the local monitor.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    private var overlayWindows: [NSWindow] = []
    private var toolbarWindow: NSWindow?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var hoverGeneration: UInt64 = 0

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
        session.onModeChange = onModeChange
        session.onAspectRatioChange = onAspectRatioChange
        session.onRequestCapture = onCapture
        session.onCancel = onCancel

        let mainScreen = NSScreen.main ?? NSScreen.screens[0]
        session.selectionRect = CaptureSessionState.defaultSelection(on: mainScreen, aspect: aspectRatio)

        for screen in NSScreen.screens {
            let window = makeOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.orderFront(nil)
        }

        toolbarWindow = makeToolbarWindow(on: mainScreen)
        toolbarWindow?.orderFront(nil)
        // Make one overlay key so Esc/Return are delivered reliably.
        overlayWindows.first?.makeKeyAndOrderFront(nil)

        installMonitors()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        hoverTask?.cancel()
        hoverTask = nil
        removeMonitors()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
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

    private func makeToolbarWindow(on screen: NSScreen) -> NSWindow {
        let size = NSSize(width: 520, height: 72)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 36
        )
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
        window.contentView = NSHostingView(
            rootView: CaptureToolbarView(session: session)
                .frame(width: size.width, height: size.height)
        )
        return window
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

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(event)
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard session.mode == .window else { return }
        let location = NSEvent.mouseLocation
        scheduleHoverUpdate(at: location)
    }

    private func scheduleHoverUpdate(at location: NSPoint) {
        hoverTask?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        hoverTask = Task { @MainActor in
            // Debounce rapid mouse moves before hitting SCShareableContent.
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, generation == hoverGeneration else { return }
            await updateHoveredWindow(at: location, generation: generation)
        }
    }

    private func updateHoveredWindow(at location: NSPoint, generation: UInt64) async {
        do {
            let windows = try await ScreenshotCaptureService.fetchWindows()
            guard !Task.isCancelled, generation == hoverGeneration else { return }

            // Frontmost-first list: first containing frame wins.
            let hit = windows.first { window in
                let frame = ScreenshotCaptureService.convertSCWindowFrameToAppKit(window.frame)
                return frame.contains(location)
            }
            guard generation == hoverGeneration else { return }

            session.hoveredWindowID = hit?.windowID
            // Keep selected in sync with hover so highlight and capture stay aligned.
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
}
