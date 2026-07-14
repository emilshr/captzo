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
        }
        .defaultSize(width: 960, height: 640)
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
        }
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
    }

    private func presentGallery() {
        appState.openGallery()
        openWindow(id: "gallery")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        HotkeyManager.shared.reregisterFromPreferences {
            AppState.shared.startCapture()
        }

        NotificationCenter.default.addObserver(
            forName: .openGalleryWindow,
            object: nil,
            queue: .main
        ) { _ in
            Self.openGalleryViaURL()
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
        for url in urls where url.host == "gallery" || url.absoluteString.contains("gallery") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func openGalleryViaURL() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let url = URL(string: "scratio://gallery") {
            NSWorkspace.shared.open(url)
        }
    }
}
