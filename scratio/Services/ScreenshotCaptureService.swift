import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenshotCaptureService {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case noDisplay
        case captureFailed(String)
        case windowNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen Recording permission is required. Enable it in System Settings → Privacy & Security → Screen Recording."
            case .noDisplay:
                return "No display available to capture."
            case .captureFailed(let message):
                return "Capture failed: \(message)"
            case .windowNotFound:
                return "Selected window is no longer available."
            }
        }
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

    /// Returns on-screen app windows frontmost-first (lower `windowLayer` first; later source index wins ties).
    static func fetchWindows() async throws -> [SCWindow] {
        try await ensurePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let filtered = content.windows.enumerated().filter { _, window in
            guard let app = window.owningApplication else { return false }
            if app.processID == ownPID { return false }
            if window.frame.width < 40 || window.frame.height < 40 { return false }
            return window.isOnScreen
        }
        return filtered
            .sorted { lhs, rhs in
                if lhs.element.windowLayer != rhs.element.windowLayer {
                    return lhs.element.windowLayer < rhs.element.windowLayer
                }
                // Later in SCShareableContent is preferred when layers match.
                return lhs.offset > rhs.offset
            }
            .map(\.element)
    }

    /// Hit-tests `location` (AppKit global) against windows ordered frontmost-first.
    static func windowAt(
        point location: CGPoint,
        in windows: [SCWindow]
    ) -> SCWindow? {
        windows.first { window in
            convertSCWindowFrameToAppKit(window.frame).contains(location)
        }
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
        let granted = requestScreenCaptureAccess()
        if !granted && !hasScreenCaptureAccess() {
            throw CaptureError.permissionDenied
        }
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
