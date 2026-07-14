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

        // SCScreenshotManager.captureImage(in:) expects display space in points.
        // Convert from AppKit bottom-left global coords to top-left screen space used by SCK on modern macOS.
        let captureRect = convertToCaptureSpace(rect)

        do {
            let cgImage = try await SCScreenshotManager.captureImage(in: captureRect)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
        config.width = max(Int(frame.width), 1)
        config.height = max(Int(frame.height), 1)
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

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
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
    }

    private static func ensurePermission() async throws {
        if hasScreenCaptureAccess() { return }
        let granted = requestScreenCaptureAccess()
        if !granted && !hasScreenCaptureAccess() {
            throw CaptureError.permissionDenied
        }
    }

    /// Converts AppKit global rect (origin bottom-left) to the coordinate space expected by
    /// `SCScreenshotManager.captureImage(in:)`, which uses top-left origin in display space.
    private static func convertToCaptureSpace(_ appKitRect: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitRect) })
                ?? NSScreen.main else {
            return appKitRect
        }

        let screenFrame = screen.frame
        // Flip Y relative to the primary coordinate system used by AppKit.
        // Global AppKit Y grows upward; capture APIs typically use top-left.
        let primaryHeight = NSScreen.screens.map(\.frame.maxY).max() ?? screenFrame.maxY
        let flippedY = primaryHeight - appKitRect.origin.y - appKitRect.height
        return CGRect(
            x: appKitRect.origin.x,
            y: flippedY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }
}
