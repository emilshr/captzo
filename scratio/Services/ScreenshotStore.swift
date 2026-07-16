import AppKit
import Foundation

private enum ScreenshotFileIO {
    static func loadImage(at url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    static func listScreenshots(
        screenshotsDirectory: URL,
        metadataDirectory: URL,
        sortOrder: GallerySortOrder
    ) -> [CapturedScreenshot] {
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)

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
            let meta = loadMetadata(for: url, metadataDirectory: metadataDirectory)
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

        return switch sortOrder {
        case .newestFirst:
            items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            items.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private static func metadataURL(for imageURL: URL, metadataDirectory: URL) -> URL {
        metadataDirectory.appendingPathComponent("\(imageURL.deletingPathExtension().lastPathComponent).json")
    }

    private static func loadMetadata(for imageURL: URL, metadataDirectory: URL) -> ScreenshotMetadata? {
        let url = metadataURL(for: imageURL, metadataDirectory: metadataDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScreenshotMetadata.self, from: data)
    }
}

@MainActor
final class ScreenshotStore {
    static let shared = ScreenshotStore()

    private let fileManager = FileManager.default

    var screenshotsDirectory: URL {
        Self.migrateLegacyStoreIfNeeded()
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory is unavailable.")
        }
        return base
            .appendingPathComponent("captzo", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
    }

    private var metadataDirectory: URL {
        screenshotsDirectory.appendingPathComponent("Metadata", isDirectory: true)
    }

    private init() {
        try? ensureDirectories()
    }

    /// Moves `Application Support/scratio` → `captzo` once when upgrading.
    private static func migrateLegacyStoreIfNeeded() {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let legacy = base.appendingPathComponent("scratio", isDirectory: true)
        let current = base.appendingPathComponent("captzo", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        if fileManager.fileExists(atPath: current.path) { return }
        try? fileManager.moveItem(at: legacy, to: current)
    }

    func ensureDirectories() throws {
        try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    func listScreenshots(sortOrder: GallerySortOrder) async -> [CapturedScreenshot] {
        let screenshotsDirectory = screenshotsDirectory
        let metadataDirectory = metadataDirectory
        return await Task.detached(priority: .userInitiated) {
            ScreenshotFileIO.listScreenshots(
                screenshotsDirectory: screenshotsDirectory,
                metadataDirectory: metadataDirectory,
                sortOrder: sortOrder
            )
        }.value
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

    func loadImage(for screenshot: CapturedScreenshot) async -> NSImage? {
        let url = screenshot.fileURL
        return await Task.detached(priority: .userInitiated) {
            ScreenshotFileIO.loadImage(at: url)
        }.value
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
