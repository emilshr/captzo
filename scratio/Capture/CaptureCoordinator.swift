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
        // Prefer live hover over a stale tap so the highlight matches the shot.
        let windowID = session.hoveredWindowID ?? session.selectedWindowID
        let displayID = session.selectedDisplayID
        let selectionRect = session.selectionRect

        overlay.hide()

        captureTask?.cancel()
        captureTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            do {
                let image: NSImage
                switch mode {
                case .selection:
                    guard selectionRect.width > 2, selectionRect.height > 2 else {
                        cancelHandler?()
                        return
                    }
                    image = try await ScreenshotCaptureService.captureRegion(selectionRect)
                case .window:
                    guard let windowID else {
                        cancelHandler?()
                        return
                    }
                    image = try await ScreenshotCaptureService.captureWindow(windowID: windowID)
                case .display:
                    let id = displayID ?? displayIDUnderMouse()
                    image = try await ScreenshotCaptureService.captureDisplay(id)
                }

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
