import AppKit
import SwiftUI

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var screenshots: [CapturedScreenshot] = []
    var sortOrder: GallerySortOrder = AppPreferences.sortOrder {
        didSet {
            AppPreferences.sortOrder = sortOrder
            reloadScreenshots()
        }
    }

    var aspectRatio: AspectRatioOption = AppPreferences.aspectRatio {
        didSet { AppPreferences.aspectRatio = aspectRatio }
    }

    var captureMode: CaptureMode = .selection
    var isCapturing = false
    var selectedScreenshot: CapturedScreenshot?
    var statusMessage: String?
    var showPermissionAlert = false
    var permissionAlertMessage = ""
    /// Bumped to request the Gallery window from a SwiftUI scene that owns `openWindow`.
    var galleryOpenToken: Int = 0

    let captureCoordinator = CaptureCoordinator()

    private init() {
        reloadScreenshots()
    }

    func reloadScreenshots() {
        screenshots = ScreenshotStore.shared.listScreenshots(sortOrder: sortOrder)
    }

    func startCapture() {
        guard !isCapturing else { return }

        if !ScreenshotCaptureService.hasScreenCaptureAccess() {
            let granted = ScreenshotCaptureService.requestScreenCaptureAccess()
            if !granted && !ScreenshotCaptureService.hasScreenCaptureAccess() {
                permissionAlertMessage = ScreenshotCaptureService.CaptureError.permissionDenied.localizedDescription
                showPermissionAlert = true
                return
            }
        }

        isCapturing = true
        captureCoordinator.start(
            mode: captureMode,
            aspectRatio: aspectRatio,
            onModeChange: { [weak self] mode in
                self?.captureMode = mode
            },
            onAspectRatioChange: { [weak self] ratio in
                self?.aspectRatio = ratio
            },
            onCapture: { [weak self] image, mode, ratio in
                await self?.handleCapturedImage(image, mode: mode, ratio: ratio)
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            }
        )
    }

    func cancelCapture() {
        captureCoordinator.stop()
        isCapturing = false
    }

    func delete(_ screenshot: CapturedScreenshot) {
        do {
            try ScreenshotStore.shared.delete(screenshot)
            if selectedScreenshot?.id == screenshot.id {
                selectedScreenshot = nil
            }
            reloadScreenshots()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func copyToClipboard(_ screenshot: CapturedScreenshot) {
        ClipboardService.copy(contentsOf: screenshot.fileURL)
        statusMessage = "Copied to clipboard"
    }

    func openGallery() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.title == "Gallery" || $0.identifier?.rawValue == "gallery"
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        galleryOpenToken &+= 1
        NotificationCenter.default.post(name: .openGalleryWindow, object: nil)
        if let url = URL(string: "scratio://gallery") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleCapturedImage(
        _ image: NSImage,
        mode: CaptureMode,
        ratio: AspectRatioOption
    ) async {
        ClipboardService.copy(image)

        do {
            let item = try ScreenshotStore.shared.save(
                image: image,
                aspectRatio: ratio,
                captureMode: mode
            )
            reloadScreenshots()
            statusMessage = "Screenshot copied & saved"
            selectedScreenshot = item

            if AppPreferences.openGalleryAfterCapture {
                openGallery()
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        isCapturing = false
    }
}

extension Notification.Name {
    static let openGalleryWindow = Notification.Name("scratio.openGalleryWindow")
    static let openSettingsWindow = Notification.Name("scratio.openSettingsWindow")
}
