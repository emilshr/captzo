import AppKit
import SwiftUI

@main
struct scratioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("Scratio", systemImage: "camera.viewfinder") {
            MenuBarContent(appState: appState)
        }

        Window("Gallery", id: "gallery") {
            GalleryView(appState: appState)
                .frame(minWidth: 720, minHeight: 480)
                .registerWindowRouter()
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "gallery"))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Capture") {
                    appState.startCapture()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .registerWindowRouter()
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarContent: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("New Capture") {
            appState.startCapture()
        }

        Button("Open Gallery") {
            presentGallery()
        }

        Divider()

        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Quit Scratio") {
            NSApp.terminate(nil)
        }
        .onAppear {
            WindowRouter.shared.register(openWindow)
        }
    }

    private func presentGallery() {
        WindowRouter.shared.register(openWindow)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "gallery")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.refreshScreenRecordingPermission()

        HotkeyManager.shared.reregisterFromPreferences {
            AppState.shared.startCapture()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.refreshScreenRecordingPermission()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openGalleryWindow,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if WindowRouter.shared.openGallery() {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
                // Fallback: external event opens the Window scene via URL scheme.
                if let url = URL(string: "scratio://gallery") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let visibleWindows = NSApp.windows.filter { window in
                    window.isVisible
                        && window.canBecomeKey
                        && !String(describing: type(of: window)).contains("StatusBar")
                        && window.level == .normal
                }
                if visibleWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "scratio", url.host == "gallery" else { continue }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                _ = WindowRouter.shared.openGallery()
            }
        }
    }
}
