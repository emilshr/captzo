import AppKit
import Foundation

@MainActor
final class ScreenshotStore {
    static let shared = ScreenshotStore()

    private let fileManager = FileManager.default

    var screenshotsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("scratio", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    private var metadataDirectory: URL {
        screenshotsDirectory.appendingPathComponent("Metadata", isDirectory: true)
    }

    private init() {
        try? ensureDirectories()
    }

    func ensureDirectories() throws {
        try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    func listScreenshots(sortOrder: GallerySortOrder) -> [CapturedScreenshot] {
        try? ensureDirectories()

        guard let urls = try? fileManager.contentsOfDirectory(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let pngs = urls.filter { $0.pathExtension.lowercased() == "png" }
        var items: [CapturedScreenshot] = []

        for url in pngs {
            let meta = loadMetadata(for: url)
            let createdAt = meta?.createdAt
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast
            let id = meta?.id ?? UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            items.append(
                CapturedScreenshot(
                    id: id,
                    fileURL: url,
                    createdAt: createdAt,
                    aspectRatioRaw: meta?.aspectRatio
                )
            )
        }

        switch sortOrder {
        case .newestFirst:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return items.sorted { $0.createdAt < $1.createdAt }
        }
    }

    func save(
        image: NSImage,
        aspectRatio: AspectRatioOption,
        captureMode: CaptureMode
    ) throws -> CapturedScreenshot {
        try ensureDirectories()

        let id = UUID()
        let createdAt = Date()
        let filename = "\(id.uuidString).png"
        let fileURL = screenshotsDirectory.appendingPathComponent(filename)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw StoreError.encodeFailed
        }

        try png.write(to: fileURL)

        let metadata = ScreenshotMetadata(
            id: id,
            createdAt: createdAt,
            aspectRatio: aspectRatio.rawValue,
            captureMode: captureMode.rawValue
        )
        try saveMetadata(metadata, for: fileURL)

        return CapturedScreenshot(
            id: id,
            fileURL: fileURL,
            createdAt: createdAt,
            aspectRatioRaw: aspectRatio.rawValue
        )
    }

    func delete(_ screenshot: CapturedScreenshot) throws {
        try fileManager.removeItem(at: screenshot.fileURL)
        let metaURL = metadataURL(for: screenshot.fileURL)
        if fileManager.fileExists(atPath: metaURL.path) {
            try fileManager.removeItem(at: metaURL)
        }
    }

    func loadImage(for screenshot: CapturedScreenshot) -> NSImage? {
        NSImage(contentsOf: screenshot.fileURL)
    }

    func revealInFinder(_ screenshot: CapturedScreenshot) {
        NSWorkspace.shared.activateFileViewerSelecting([screenshot.fileURL])
    }

    private func metadataURL(for imageURL: URL) -> URL {
        metadataDirectory.appendingPathComponent("\(imageURL.deletingPathExtension().lastPathComponent).json")
    }

    private func saveMetadata(_ metadata: ScreenshotMetadata, for imageURL: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(for: imageURL), options: .atomic)
    }

    private func loadMetadata(for imageURL: URL) -> ScreenshotMetadata? {
        let url = metadataURL(for: imageURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScreenshotMetadata.self, from: data)
    }

    enum StoreError: LocalizedError {
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .encodeFailed:
                return "Failed to encode screenshot as PNG."
            }
        }
    }
}
