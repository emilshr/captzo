import AppKit
import SwiftUI

@main
struct scratioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @State private var languageStore: LanguageStore

    init() {
        let store = LanguageStore()
        LanguageStore.install(store)
        _languageStore = State(initialValue: store)
        _appState = State(initialValue: AppState.shared)
    }

    var body: some Scene {
        let store = installedLanguageStore
        let galleryTitle = store.tr("Gallery")
        let newCaptureTitle = store.tr("New Capture")

        MenuBarExtra("Captzo", systemImage: "camera.viewfinder") {
            MenuBarContent()
                .environment(appState)
                .scratioLocalized(store)
        }

        Window(galleryTitle, id: "gallery") {
            GalleryView()
                .environment(appState)
                .scratioLocalized(store)
                .frame(minWidth: 720, minHeight: 480)
                .registerWindowRouter()
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "gallery"))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(newCaptureTitle) {
                    appState.startCapture()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .scratioLocalized(store)
                .registerWindowRouter()
        }
        .defaultSize(width: 560, height: 520)
        .windowResizability(.contentMinSize)
    }

    private var installedLanguageStore: LanguageStore {
        LanguageStore.install(languageStore)
        return languageStore
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var appState = appState

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

        Button("Quit Captzo") {
            NSApp.terminate(nil)
        }
        .task {
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
                if let url = URL(string: "captzo://gallery") {
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
            guard url.scheme == "captzo", url.host == "gallery" else { continue }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                _ = WindowRouter.shared.openGallery()
            }
        }
    }
}
