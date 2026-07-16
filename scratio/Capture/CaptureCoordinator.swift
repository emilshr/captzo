import AppKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let overlay = OverlayWindowController()
    private var captureHandler: ((NSImage, CaptureMode, AspectRatioOption) async -> Void)?
    private var cancelHandler: (() -> Void)?
    private var captureTask: Task<Void, Never>?

    func start(
        mode: CaptureMode,
        aspectRatio: AspectRatioOption,
        onModeChange: @escaping (CaptureMode) -> Void,
        onAspectRatioChange: @escaping (AspectRatioOption) -> Void,
        onCapture: @escaping (NSImage, CaptureMode, AspectRatioOption) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        captureTask?.cancel()
        captureTask = nil
        captureHandler = onCapture
        cancelHandler = onCancel

        overlay.show(
            mode: mode,
            aspectRatio: aspectRatio,
            onModeChange: onModeChange,
            onAspectRatioChange: onAspectRatioChange,
            onCapture: { [weak self] in
                self?.performCapture()
            },
            onCancel: { [weak self] in
                self?.stop()
                onCancel()
            }
        )
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        overlay.hide()
    }

    private func performCapture() {
        let session = overlay.session
        let mode = session.mode
        let ratio = session.aspectRatio
        let windowID = session.pointer.hoveredWindowID ?? session.pointer.selectedWindowID
        let displayID = session.pointer.selectedDisplayID
        let selectionRect = session.selectionRect

        guard canStartCapture(mode: mode, windowID: windowID, selectionRect: selectionRect) else {
            return
        }

        overlay.hide()

        captureTask?.cancel()
        captureTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            do {
                let image = try await captureImage(
                    mode: mode,
                    windowID: windowID,
                    displayID: displayID,
                    selectionRect: selectionRect
                )
                guard !Task.isCancelled else { return }
                await captureHandler?(image, mode, ratio)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let mapped = ScreenshotCaptureService.mapCaptureError(error)
                presentCaptureError(mapped)
                cancelHandler?()
            }
        }
    }

    private func canStartCapture(
        mode: CaptureMode,
        windowID: CGWindowID?,
        selectionRect: CGRect
    ) -> Bool {
        switch mode {
        case .window:
            return windowID != nil
        case .selection:
            return selectionRect.width > 2 && selectionRect.height > 2
        case .display:
            return true
        }
    }

    private func captureImage(
        mode: CaptureMode,
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID?,
        selectionRect: CGRect
    ) async throws -> NSImage {
        switch mode {
        case .selection:
            return try await ScreenshotCaptureService.captureRegion(selectionRect)
        case .window:
            guard let windowID else {
                throw ScreenshotCaptureService.CaptureError.captureFailed("No window selected.")
            }
            return try await ScreenshotCaptureService.captureWindow(windowID: windowID)
        case .display:
            let id = displayID ?? displayIDUnderMouse()
            return try await ScreenshotCaptureService.captureDisplay(id)
        }
    }

    private func presentCaptureError(_ error: Error) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let captureError = error as? ScreenshotCaptureService.CaptureError,
           case .permissionDenied = captureError {
            AppState.shared.showCapturePermissionError(captureError)
            return
        }
        if let captureError = error as? ScreenshotCaptureService.CaptureError,
           case .permissionRestartRequired = captureError {
            AppState.shared.showCapturePermissionError(captureError)
            return
        }
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func displayIDUnderMouse() -> CGDirectDisplayID {
        CaptureSessionState.displayID(at: NSEvent.mouseLocation)
    }
}
