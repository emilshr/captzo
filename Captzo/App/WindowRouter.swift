import SwiftUI

/// Holds `openWindow` so gallery can be opened while the menu bar menu is closed.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    private var openWindow: OpenWindowAction?

    func register(_ openWindow: OpenWindowAction) {
        self.openWindow = openWindow
    }

    @discardableResult
    func openGallery() -> Bool {
        guard let openWindow else { return false }
        openWindow(id: "gallery")
        return true
    }
}

struct WindowRouterRegistrar: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .task {
                WindowRouter.shared.register(openWindow)
            }
    }
}

extension View {
    func registerWindowRouter() -> some View {
        modifier(WindowRouterRegistrar())
    }
}
