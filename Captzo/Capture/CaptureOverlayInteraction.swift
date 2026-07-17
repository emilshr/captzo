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
    private var mouseMoveCoalesceScheduled = false
    private var mouseDragCoalesceScheduled = false

    private let session: () -> CaptureSessionState?
    private let toolbarFrame: () -> CGRect?
    private let onMakeOverlayKey: (CGPoint) -> Void
    private let onCursorUpdate: () -> Void
    private let onCursorReset: () -> Void

    init(
        session: @escaping () -> CaptureSessionState?,
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
            guard let self, let session = self.session() else { return event }
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
            self?.enqueueMouseMoved()
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
            self?.enqueueMouseDragged()
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
        mouseMoveCoalesceScheduled = false
        mouseDragCoalesceScheduled = false

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

    private func enqueueMouseMoved() {
        guard !mouseMoveCoalesceScheduled else { return }
        mouseMoveCoalesceScheduled = true
        Task { @MainActor in
            self.mouseMoveCoalesceScheduled = false
            self.handleMouseMoved()
        }
    }

    private func enqueueMouseDragged() {
        guard !mouseDragCoalesceScheduled else { return }
        mouseDragCoalesceScheduled = true
        Task { @MainActor in
            self.mouseDragCoalesceScheduled = false
            self.handleSelectionMouseDragged()
        }
    }

    private func handleMouseMoved() {
        guard let session = session() else { return }
        let location = NSEvent.mouseLocation
        let overToolbar = toolbarFrame()?.contains(location) == true

        if !session.isSelectionInteracting, !overToolbar {
            onMakeOverlayKey(location)
        }

        switch session.mode {
        case .window:
            scheduleHoverUpdate(at: location)
            onCursorUpdate()
        case .display:
            session.pointer.selectedDisplayID = CaptureSessionState.displayID(at: location)
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

        guard let session = session() else { return false }
        switch session.mode {
        case .selection:
            session.beginSelectionInteraction(at: location)
            return false
        case .window:
            guard resolveWindowTarget(at: location, session: session) else {
                // Block click-through even when no window is under the cursor.
                return true
            }
            session.onRequestCapture?()
            return true
        case .display:
            session.onRequestCapture?()
            return true
        }
    }

    /// Ensures pointer state has a window target, using a sync cache hit-test when hover is stale.
    @discardableResult
    private func resolveWindowTarget(at location: NSPoint, session: CaptureSessionState) -> Bool {
        if session.pointer.hoveredWindowID != nil || session.pointer.selectedWindowID != nil {
            return true
        }
        guard !cachedWindows.isEmpty,
              let hit = ScreenshotCaptureService.windowAt(point: location, in: cachedWindows) else {
            return false
        }
        applyWindowHit(hit, to: session)
        return true
    }

    private func applyWindowHit(_ hit: SCWindow, to session: CaptureSessionState) {
        session.pointer.hoveredWindowID = hit.windowID
        session.pointer.selectedWindowID = hit.windowID
        session.pointer.hoveredWindowFrame = ScreenshotCaptureService.convertSCWindowFrameToAppKit(hit.frame)
    }

    private func handleSelectionMouseDragged() {
        guard let session = session() else { return }
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.updateSelectionInteraction(at: NSEvent.mouseLocation)
    }

    private func handleSelectionMouseUp() {
        guard let session = session() else { return }
        guard session.mode == .selection, session.isSelectionInteracting else { return }
        session.endSelectionInteraction(persist: true)
    }

    private func updateHoveredWindow(generation: UInt64) async {
        do {
            let windows = try await fetchWindowsForHover()
            guard !Task.isCancelled, generation == hoverGeneration else { return }

            let location = NSEvent.mouseLocation
            let hit = ScreenshotCaptureService.windowAt(point: location, in: windows)
            guard generation == hoverGeneration, let session = session() else { return }

            if let hit {
                applyWindowHit(hit, to: session)
            } else {
                session.pointer.hoveredWindowID = nil
                session.pointer.selectedWindowID = nil
                session.pointer.hoveredWindowFrame = .zero
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
