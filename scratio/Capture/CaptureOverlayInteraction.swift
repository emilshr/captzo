import AppKit
import ScreenCaptureKit

/// Mouse/keyboard monitors and window hover tracking for the capture overlay.
@MainActor
final class CaptureOverlayInteraction {
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

    private let session: () -> CaptureSessionState
    private let toolbarFrame: () -> CGRect?
    private let onMakeOverlayKey: (CGPoint) -> Void
    private let onCursorUpdate: () -> Void
    private let onCursorReset: () -> Void

    init(
        session: @escaping () -> CaptureSessionState,
        toolbarFrame: @escaping () -> CGRect?,
        onMakeOverlayKey: @escaping (CGPoint) -> Void,
        onCursorUpdate: @escaping () -> Void,
        onCursorReset: @escaping () -> Void
    ) {
        self.session = session
        self.toolbarFrame = toolbarFrame
        self.onMakeOverlayKey = onMakeOverlayKey
        self.onCursorUpdate = onCursorUpdate
        self.onCursorReset = onCursorReset
    }

    func install() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let session = self.session()
            if event.keyCode == 53 { // Escape
                session.onCancel?()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad enter
                session.onRequestCapture?()
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

    func remove() {
        hoverTask?.cancel()
        hoverTask = nil
        cachedWindows = []
        windowsCacheTime = .distantPast

        let monitors: [Any?] = [
            keyMonitor, mouseMovedLocal, mouseMovedGlobal,
            mouseDownLocal, mouseDraggedLocal, mouseUpLocal,
            mouseDraggedGlobal, mouseUpGlobal
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

    func scheduleHoverUpdate(at location: NSPoint) {
        hoverTask?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, generation == hoverGeneration else { return }
            await updateHoveredWindow(generation: generation)
        }
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        let session = session()
        if !session.isSelectionInteracting {
            onMakeOverlayKey(location)
        }

        switch session.mode {
        case .window:
            scheduleHoverUpdate(at: location)
            onCursorUpdate()
        case .display:
            session.selectedDisplayID = CaptureSessionState.displayID(at: location)
            onCursorUpdate()
        case .selection:
            onCursorReset()
        }
    }

    /// Returns `true` when the event should be swallowed.
    private func handleMouseDown() -> Bool {
        let location = NSEvent.mouseLocation
        if let toolbar = toolbarFrame(), toolbar.contains(location) {
            return false
        }

        let session = session()
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
            session.onRequestCapture?()
            return true
        }
    }

    private func handleSelectionMouseDragged() {
        let session = session()
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.updateSelectionInteraction(at: NSEvent.mouseLocation)
    }

    private func handleSelectionMouseUp() {
        let session = session()
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.endSelectionInteraction(persist: true)
    }

    private func updateHoveredWindow(generation: UInt64) async {
        do {
            let windows = try await fetchWindowsForHover()
            guard !Task.isCancelled, generation == hoverGeneration else { return }

            let location = NSEvent.mouseLocation
            let hit = ScreenshotCaptureService.windowAt(point: location, in: windows)
            guard generation == hoverGeneration else { return }

            let session = session()
            session.hoveredWindowID = hit?.windowID
            session.selectedWindowID = hit?.windowID
            if let hit {
                session.hoveredWindowFrame = ScreenshotCaptureService.convertSCWindowFrameToAppKit(hit.frame)
            } else {
                session.hoveredWindowFrame = .zero
            }
            onCursorUpdate()
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
}
