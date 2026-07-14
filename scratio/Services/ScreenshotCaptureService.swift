import AppKit
import CoreGraphics
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
            return nsImage(from: cgImage, pointSize: rect.size, scale: scale)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    static func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> NSImage {
        try await ensurePermission()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // SCDisplay.width/height are already pixel dimensions.
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        config.capturesAudio = false

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
            return nsImage(from: cgImage, pointSize: pointSize, scale: scale)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    static func captureWindow(windowID: CGWindowID) async throws -> NSImage {
        try await ensurePermission()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let frame = window.frame
        let scale = scaleFactor(forWindowFrame: frame)
        // SCStreamConfiguration expects pixel buffer size, not points.
        config.width = max(Int((frame.width * scale).rounded()), 1)
        config.height = max(Int((frame.height * scale).rounded()), 1)
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return nsImage(
                from: cgImage,
                pointSize: NSSize(width: frame.width, height: frame.height),
                scale: scale
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Returns on-screen app windows frontmost-first (lower `windowLayer` first, then list order).
    static func fetchWindows() async throws -> [SCWindow] {
        try await ensurePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows
            .filter { window in
                guard let app = window.owningApplication else { return false }
                if app.processID == ownPID { return false }
                if window.frame.width < 40 || window.frame.height < 40 { return false }
                return window.isOnScreen
            }
            .sorted { lhs, rhs in
                if lhs.windowLayer != rhs.windowLayer {
                    return lhs.windowLayer < rhs.windowLayer
                }
                // Prefer smaller windows when layers match so nested content wins over large shells.
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                return lhsArea < rhsArea
            }
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
        let primaryMaxY = primaryScreenMaxY()
        let flippedY = primaryMaxY - appKitRect.origin.y - appKitRect.height
        return CGRect(
            x: appKitRect.origin.x,
            y: flippedY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    /// Converts SCK/CG window frame (top-left) to AppKit global (bottom-left).
    static func convertSCWindowFrameToAppKit(_ frame: CGRect) -> CGRect {
        let primaryMaxY = primaryScreenMaxY()
        return CGRect(
            x: frame.origin.x,
            y: primaryMaxY - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    static func primaryScreenMaxY() -> CGFloat {
        // screens[0] is the primary (menu-bar) screen — use its maxY, not the union of all displays.
        (NSScreen.screens.first ?? NSScreen.main)?.frame.maxY ?? 0
    }

    private static func nsImage(from cgImage: CGImage, pointSize: NSSize, scale: CGFloat) -> NSImage {
        let size = NSSize(
            width: max(pointSize.width, 1),
            height: max(pointSize.height, 1)
        )
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        // Keep full-resolution pixels while advertising correct point size for pasteboard hosts.
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

    private static func scaleFactor(forWindowFrame frame: CGRect) -> CGFloat {
        let appKitFrame = convertSCWindowFrameToAppKit(frame)
        return backingScaleFactor(for: appKitFrame)
    }
}
