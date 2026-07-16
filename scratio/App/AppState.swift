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

    var captureMode: CaptureMode = AppPreferences.captureMode {
        didSet { AppPreferences.captureMode = captureMode }
    }

    var isCapturing = false
    var selectedScreenshot: CapturedScreenshot?
    var statusMessage: String?
    var showPermissionAlert = false
    var permissionAlertMessage = ""
    /// True when Screen Recording is not granted — Gallery shows a persistent banner.
    var needsScreenRecordingPermission = false
    /// Bumped to request the Gallery window from a SwiftUI scene that owns `openWindow`.
    var galleryOpenToken: Int = 0

    let captureCoordinator = CaptureCoordinator()

    private init() {
        reloadScreenshots()
        refreshScreenRecordingPermission()
    }

    func reloadScreenshots() {
        screenshots = ScreenshotStore.shared.listScreenshots(sortOrder: sortOrder)
    }

    func refreshScreenRecordingPermission() {
        needsScreenRecordingPermission = !ScreenshotCaptureService.hasScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() {
        _ = ScreenshotCaptureService.requestScreenCaptureAccess()
        refreshScreenRecordingPermission()
        if needsScreenRecordingPermission {
            permissionAlertMessage = ScreenshotCaptureService.permissionDeniedMessage
            showPermissionAlert = true
        }
    }

    func showCapturePermissionError(_ error: ScreenshotCaptureService.CaptureError) {
        permissionAlertMessage = error.localizedDescription ?? "Capture failed."
        showPermissionAlert = true
        needsScreenRecordingPermission = !ScreenshotCaptureService.hasScreenCaptureAccess()
        isCapturing = false
    }

    func startCapture() {
        guard !isCapturing else { return }

        refreshScreenRecordingPermission()
        if !ScreenshotCaptureService.hasScreenCaptureAccess() {
            _ = ScreenshotCaptureService.requestScreenCaptureAccess()
            refreshScreenRecordingPermission()
            if !ScreenshotCaptureService.hasScreenCaptureAccess() {
                permissionAlertMessage = ScreenshotCaptureService.permissionDeniedMessage
                showPermissionAlert = true
                needsScreenRecordingPermission = true
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
        if ClipboardService.copy(contentsOf: screenshot.fileURL) {
            statusMessage = "Copied to clipboard"
        } else {
            statusMessage = "Failed to copy screenshot"
        }
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
        // Prefer the registered SwiftUI openWindow action when available.
        if WindowRouter.shared.openGallery() {
            return
        }
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
