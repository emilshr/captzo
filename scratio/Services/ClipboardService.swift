import AppKit
import Foundation

enum ClipboardService {
    static func copy(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func copy(contentsOf url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        copy(image)
    }
}
