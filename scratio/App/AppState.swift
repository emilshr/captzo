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
            Task { await reloadScreenshots() }
        }
    }

    var aspectRatio: AspectRatioOption = AppPreferences.aspectRatio {
        didSet { AppPreferences.aspectRatio = aspectRatio }
    }

    var captureMode: CaptureMode = AppPreferences.captureMode {
        didSet { AppPreferences.captureMode = captureMode }
    }

    var openGalleryAfterCapture: Bool = AppPreferences.openGalleryAfterCapture {
        didSet { AppPreferences.openGalleryAfterCapture = openGalleryAfterCapture }
    }

    var clipboardToastMessage: String = AppPreferences.clipboardToastMessage {
        didSet { AppPreferences.clipboardToastMessage = clipboardToastMessage }
    }

    /// `nil` means show all aspect ratios.
    var aspectRatioFilter: AspectRatioOption?

    /// Bumped when badge colors change so SwiftUI refreshes chips.
    var badgeColorRevision: Int = 0

    var isCapturing = false
    var selectedScreenshotIDs: Set<UUID> = []
    /// Last item the user interacted with (for preview / primary actions).
    var lastSelectedScreenshotID: UUID?
    var statusMessage: String?
    var showPermissionAlert = false
    var permissionAlertMessage = ""
    /// True when Screen Recording is not granted — Gallery shows a persistent banner.
    var needsScreenRecordingPermission = false
    /// Bumped to request the Gallery window from a SwiftUI scene that owns `openWindow`.
    var galleryOpenToken: Int = 0
    var showDeleteConfirmation = false

    let captureCoordinator = CaptureCoordinator()
    private let toastController = ToastWindowController()

    private init() {
        Task { await reloadScreenshots() }
        refreshScreenRecordingPermission()
    }

    var filteredScreenshots: [CapturedScreenshot] {
        guard let aspectRatioFilter else { return screenshots }
        return screenshots.filter { $0.aspectRatioRaw == aspectRatioFilter.rawValue }
    }

    var selectedScreenshots: [CapturedScreenshot] {
        let ids = selectedScreenshotIDs
        return filteredScreenshots.filter { ids.contains($0.id) }
    }

    var primarySelectedScreenshot: CapturedScreenshot? {
        if let lastSelectedScreenshotID,
           let match = screenshots.first(where: { $0.id == lastSelectedScreenshotID }),
           selectedScreenshotIDs.contains(match.id) {
            return match
        }
        return selectedScreenshots.first
    }

    func reloadScreenshots() async {
        screenshots = await ScreenshotStore.shared.listScreenshots(sortOrder: sortOrder)
        let validIDs = Set(screenshots.map(\.id))
        selectedScreenshotIDs = selectedScreenshotIDs.intersection(validIDs)
        if let lastSelectedScreenshotID, !validIDs.contains(lastSelectedScreenshotID) {
            self.lastSelectedScreenshotID = selectedScreenshotIDs.first
        }
    }

    var screenshotsFolderPath: String {
        ScreenshotStore.shared.screenshotsDirectory.path
    }

    func selectOnly(_ screenshot: CapturedScreenshot) {
        selectedScreenshotIDs = [screenshot.id]
        lastSelectedScreenshotID = screenshot.id
    }

    func toggleSelection(_ screenshot: CapturedScreenshot) {
        if selectedScreenshotIDs.contains(screenshot.id) {
            selectedScreenshotIDs.remove(screenshot.id)
            if lastSelectedScreenshotID == screenshot.id {
                lastSelectedScreenshotID = selectedScreenshotIDs.first
            }
        } else {
            selectedScreenshotIDs.insert(screenshot.id)
            lastSelectedScreenshotID = screenshot.id
        }
    }

    func selectRange(to screenshot: CapturedScreenshot) {
        let items = filteredScreenshots
        guard let endIndex = items.firstIndex(where: { $0.id == screenshot.id }) else {
            selectOnly(screenshot)
            return
        }
        let startID = lastSelectedScreenshotID ?? selectedScreenshotIDs.first
        guard let startID,
              let startIndex = items.firstIndex(where: { $0.id == startID }) else {
            selectOnly(screenshot)
            return
        }
        let range = startIndex <= endIndex
            ? startIndex...endIndex
            : endIndex...startIndex
        selectedScreenshotIDs = Set(items[range].map(\.id))
        lastSelectedScreenshotID = screenshot.id
    }

    func handleGridClick(_ screenshot: CapturedScreenshot, flags: NSEvent.ModifierFlags) {
        if flags.contains(.command) {
            toggleSelection(screenshot)
        } else if flags.contains(.shift) {
            selectRange(to: screenshot)
        } else {
            selectOnly(screenshot)
        }
    }

    func revealInFinder(_ screenshot: CapturedScreenshot) {
        ScreenshotStore.shared.revealInFinder(screenshot)
    }

    func revealInFinder(_ screenshots: [CapturedScreenshot]) {
        let urls = screenshots.map(\.fileURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealSelectedInFinder() {
        revealInFinder(selectedScreenshots)
    }

    func revealScreenshotsFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            ScreenshotStore.shared.screenshotsDirectory
        ])
    }

    func openInDefaultApp(_ screenshot: CapturedScreenshot) {
        NSWorkspace.shared.open(screenshot.fileURL)
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
        delete(ids: [screenshot.id])
    }

    func deleteSelected() {
        delete(ids: selectedScreenshotIDs)
    }

    func delete(ids: Set<UUID>) {
        let toDelete = screenshots.filter { ids.contains($0.id) }
        for shot in toDelete {
            do {
                try ScreenshotStore.shared.delete(shot)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        selectedScreenshotIDs.subtract(ids)
        if let lastSelectedScreenshotID, ids.contains(lastSelectedScreenshotID) {
            self.lastSelectedScreenshotID = selectedScreenshotIDs.first
        }
        Task { await reloadScreenshots() }
    }

    func copyToClipboard(_ screenshot: CapturedScreenshot) {
        if ClipboardService.copy(contentsOf: screenshot.fileURL) {
            statusMessage = "Copied to clipboard"
            showClipboardToast()
        } else {
            statusMessage = "Failed to copy screenshot"
        }
    }

    func copySelectedToClipboard() {
        guard let primary = primarySelectedScreenshot else { return }
        copyToClipboard(primary)
    }

    func notifyBadgeColorsChanged() {
        badgeColorRevision &+= 1
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
        if let url = URL(string: "captzo://gallery") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleCapturedImage(
        _ image: NSImage,
        mode: CaptureMode,
        ratio: AspectRatioOption
    ) async {
        let didCopy = ClipboardService.copy(image)

        do {
            let item = try ScreenshotStore.shared.save(
                image: image,
                aspectRatio: ratio,
                captureMode: mode
            )
            await reloadScreenshots()
            if didCopy {
                statusMessage = "Screenshot copied & saved"
                showClipboardToast()
            } else {
                statusMessage = "Failed to copy screenshot"
            }
            selectOnly(item)

            if AppPreferences.openGalleryAfterCapture {
                openGallery()
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        isCapturing = false
    }

    private func showClipboardToast() {
        let message = AppPreferences.clipboardToastMessage
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        toastController.show(message: message, on: screen)
    }
}

extension Notification.Name {
    static let openGalleryWindow = Notification.Name("captzo.openGalleryWindow")
    static let openSettingsWindow = Notification.Name("captzo.openSettingsWindow")
}
