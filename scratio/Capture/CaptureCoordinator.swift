import AppKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let overlay = OverlayWindowController()
    private var captureHandler: ((NSImage, CaptureMode, AspectRatioOption) async -> Void)?
    private var cancelHandler: (() -> Void)?

    func start(
        mode: CaptureMode,
        aspectRatio: AspectRatioOption,
        onModeChange: @escaping (CaptureMode) -> Void,
        onAspectRatioChange: @escaping (AspectRatioOption) -> Void,
        onCapture: @escaping (NSImage, CaptureMode, AspectRatioOption) async -> Void,
        onCancel: @escaping () -> Void
    ) {
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
        overlay.hide()
    }

    private func performCapture() {
        let session = overlay.session
        let mode = session.mode
        let ratio = session.aspectRatio

        // Hide overlays first so they aren't in the shot
        overlay.hide()

        Task { @MainActor in
            // Brief delay so windows finish dismissing
            try? await Task.sleep(nanoseconds: 80_000_000)

            do {
                let image: NSImage
                switch mode {
                case .selection:
                    let rect = session.selectionRect
                    guard rect.width > 2, rect.height > 2 else {
                        cancelHandler?()
                        return
                    }
                    image = try await ScreenshotCaptureService.captureRegion(rect)
                case .window:
                    let windowID = session.selectedWindowID ?? session.hoveredWindowID
                    guard let windowID else {
                        cancelHandler?()
                        return
                    }
                    image = try await ScreenshotCaptureService.captureWindow(windowID: windowID)
                case .display:
                    let displayID = session.selectedDisplayID ?? displayIDUnderMouse()
                    image = try await ScreenshotCaptureService.captureDisplay(displayID)
                }

                await captureHandler?(image, mode, ratio)
            } catch {
                NSAlert(error: error).runModal()
                cancelHandler?()
            }
        }
    }

    private func displayIDUnderMouse() -> CGDirectDisplayID {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        if let num = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(num.uint32Value)
        }
        return CGMainDisplayID()
    }
}
