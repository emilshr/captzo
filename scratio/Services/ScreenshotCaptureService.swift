import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenshotCaptureService {
    static let screenRecordingRestartHint =
        "After granting or changing Screen Recording permission, quit Scratio and relaunch it for capture to work."

    enum CaptureError: LocalizedError {
        case permissionDenied
        case permissionRestartRequired
        case noDisplay
        case captureFailed(String)
        case windowNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return permissionDeniedMessage
            case .permissionRestartRequired:
                return permissionRestartRequiredMessage
            case .noDisplay:
                return "No display available to capture."
            case .captureFailed(let message):
                return "Capture failed: \(message)"
            case .windowNotFound:
                return "Selected window is no longer available."
            }
        }
    }

    static var permissionDeniedMessage: String {
        "Screen Recording permission is required. Enable Scratio in System Settings → Privacy & Security → Screen Recording. \(screenRecordingRestartHint)"
    }

    static var permissionRestartRequiredMessage: String {
        "Screen Recording permission changed. \(screenRecordingRestartHint)"
    }

    static func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures a rectangular region in global screen coordinates (AppKit / Cocoa points, origin bottom-left).
    static func captureRegion(_ rect: CGRect) async throws -> NSImage {
        try await ensurePermission()

        let captureRect = convertToCaptureSpace(rect)
        let scale = backingScaleFactor(for: rect)

        do {
            let cgImage = try await SCScreenshotManager.captureImage(in: captureRect)
            return try nsImage(from: cgImage, pointSize: rect.size, scale: scale, rejectBlank: false)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    static func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> NSImage {
        try await ensurePermission()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = makeStreamConfiguration(
            width: display.width,
            height: display.height
        )

        let scale = scaleFactor(forDisplayID: display.displayID)
        let pointSize = NSSize(
            width: CGFloat(display.width) / scale,
            height: CGFloat(display.height) / scale
        )

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return try nsImage(from: cgImage, pointSize: pointSize, scale: scale, rejectBlank: false)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    static func captureWindow(windowID: CGWindowID) async throws -> NSImage {
        try await ensurePermission()

        // Always re-fetch shareable content so the SCWindow is fresh after overlays hide.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        if window.frame.width < 1 || window.frame.height < 1 {
            throw CaptureError.captureFailed("Window has zero size.")
        }

        var lastError: Error?
        do {
            return try await captureWindowIndependent(window)
        } catch {
            lastError = error
        }

        do {
            return try await captureWindowViaDisplay(window, content: content)
        } catch {
            throw lastError ?? error
        }
    }

    /// Window IDs from front to back (CGWindowList order).
    static func orderedOnScreenWindowIDs() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let num = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            return CGWindowID(num.uint32Value)
        }
    }

    /// Returns on-screen app windows suitable for window capture picking.
    static func fetchWindows() async throws -> [SCWindow] {
        try await ensurePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let displayFrames = NSScreen.screens.map(\.frame)
        return content.windows.filter { window in
            isPickableWindow(window, ownPID: ownPID, displayFrames: displayFrames)
        }
    }

    static func isPickableWindow(
        _ window: SCWindow,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        displayFrames: [CGRect] = NSScreen.screens.map(\.frame)
    ) -> Bool {
        guard let app = window.owningApplication else { return false }
        if app.processID == ownPID { return false }
        if window.frame.width < 40 || window.frame.height < 40 { return false }
        if !window.isOnScreen { return false }
        if !ScreenGeometry.isPickableWindowTitle(window.title) { return false }
        if !ScreenGeometry.isPickableWindowLayer(window.windowLayer) { return false }
        let appKitFrame = convertSCWindowFrameToAppKit(window.frame)
        if ScreenGeometry.isNearDisplaySized(frame: appKitFrame, displayFrames: displayFrames) {
            return false
        }
        return true
    }

    /// Hit-tests `location` (AppKit global) using CGWindow z-order, then layer fallback.
    static func windowAt(
        point location: CGPoint,
        in windows: [SCWindow]
    ) -> SCWindow? {
        let candidates = windows.enumerated().map { index, window in
            ScreenGeometry.WindowHitCandidate(
                id: window.windowID,
                frame: convertSCWindowFrameToAppKit(window.frame),
                windowLayer: window.windowLayer,
                sourceIndex: index
            )
        }
        let windowByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })

        if let hitID = ScreenGeometry.frontmostWindowID(
            at: location,
            orderedWindowIDs: orderedOnScreenWindowIDs(),
            candidates: candidates
        ), let hit = windowByID[hitID] {
            return hit
        }

        if let fallback = ScreenGeometry.frontmostWindow(at: location, in: candidates) {
            return windowByID[fallback.id]
        }
        return nil
    }

    private static func captureWindowIndependent(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        guard let pixelSize = ScreenGeometry.capturePixelSize(
            contentRect: filter.contentRect,
            pointPixelScale: scale
        ) else {
            throw CaptureError.captureFailed("Invalid window content metrics.")
        }

        let config = makeStreamConfiguration(width: pixelSize.width, height: pixelSize.height)
        config.ignoreShadowsSingleWindow = true

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return try nsImage(
            from: cgImage,
            pointSize: NSSize(width: filter.contentRect.width, height: filter.contentRect.height),
            scale: scale,
            rejectBlank: true
        )
    }

    private static func captureWindowViaDisplay(
        _ window: SCWindow,
        content: SCShareableContent
    ) async throws -> NSImage {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, including: [window])
        let scale = CGFloat(filter.pointPixelScale)
        guard let pixelSize = ScreenGeometry.capturePixelSize(
            contentRect: filter.contentRect,
            pointPixelScale: scale
        ) else {
            throw CaptureError.captureFailed("Invalid window content metrics.")
        }

        let config = makeStreamConfiguration(width: pixelSize.width, height: pixelSize.height)
        config.ignoreShadowsSingleWindow = true

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return try nsImage(
            from: cgImage,
            pointSize: NSSize(width: filter.contentRect.width, height: filter.contentRect.height),
            scale: scale,
            rejectBlank: true
        )
    }

    private static func makeStreamConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(width, 1)
        config.height = max(height, 1)
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    private static func ensurePermission() async throws {
        if hasScreenCaptureAccess() { return }
        _ = requestScreenCaptureAccess()
        if hasScreenCaptureAccess() { return }
        throw CaptureError.permissionDenied
    }

    static func mapCaptureError(_ error: Error) -> CaptureError {
        if let captureError = error as? CaptureError {
            return captureError
        }
        let description = error.localizedDescription.lowercased()
        if description.contains("declined") || description.contains("permission") {
            return hasScreenCaptureAccess() ? .permissionRestartRequired : .permissionDenied
        }
        return .captureFailed(error.localizedDescription)
    }

    /// Converts AppKit global rect (origin bottom-left) to Quartz/SCK space using the primary screen baseline.
    static func convertToCaptureSpace(_ appKitRect: CGRect) -> CGRect {
        ScreenGeometry.convertToCaptureSpace(appKitRect, primaryMaxY: primaryScreenMaxY())
    }

    /// Converts SCK/CG window frame (top-left) to AppKit global (bottom-left).
    static func convertSCWindowFrameToAppKit(_ frame: CGRect) -> CGRect {
        ScreenGeometry.convertSCWindowFrameToAppKit(frame, primaryMaxY: primaryScreenMaxY())
    }

    static func primaryScreenMaxY() -> CGFloat {
        (NSScreen.screens.first ?? NSScreen.main)?.frame.maxY ?? 0
    }

    private static func nsImage(
        from cgImage: CGImage?,
        pointSize: NSSize,
        scale: CGFloat,
        rejectBlank: Bool
    ) throws -> NSImage {
        guard let cgImage, cgImage.width > 0, cgImage.height > 0 else {
            throw CaptureError.captureFailed("Capture returned an empty image.")
        }
        if rejectBlank, ScreenGeometry.isNearlyBlank(cgImage) {
            throw CaptureError.captureFailed("Capture returned a blank image.")
        }
        let size = NSSize(
            width: max(pointSize.width, 1),
            height: max(pointSize.height, 1)
        )
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        _ = scale
        return image
    }

    private static func backingScaleFactor(for rect: CGRect) -> CGFloat {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    private static func scaleFactor(forDisplayID displayID: CGDirectDisplayID) -> CGFloat {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == displayID {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }
}
