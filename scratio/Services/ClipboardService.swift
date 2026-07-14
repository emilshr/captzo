import AppKit
import Foundation

enum ClipboardService {
    @discardableResult
    static func copy(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    @discardableResult
    static func copy(contentsOf url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        return copy(image)
    }
}
