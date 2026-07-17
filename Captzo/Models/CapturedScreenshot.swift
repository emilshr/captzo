import Foundation

struct CapturedScreenshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let aspectRatioRaw: String?

    var filename: String { fileURL.lastPathComponent }

    var aspectRatioLabel: String {
        AspectRatioOption.fromPersisted(aspectRatioRaw)?.displayName ?? aspectRatioRaw ?? "Unknown"
    }
}

struct ScreenshotMetadata: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var aspectRatio: String?
    var captureMode: String?
}
