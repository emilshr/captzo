import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var hotkeyDisplay = HotkeyManager.displayString(
        keyCode: AppPreferences.hotkeyKeyCode,
        modifiers: AppPreferences.hotkeyModifiers
    )
    @State private var isRecordingHotkey = false
    @State private var monitor: Any?

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Capture") {
                Picker("Default Aspect Ratio", selection: $appState.aspectRatio) {
                    ForEach(AspectRatioOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                Toggle("Open Gallery After Capture", isOn: $appState.openGalleryAfterCapture)
            }

            Section("Feedback") {
                TextField("Copied to clipboard", text: $appState.clipboardToastMessage)
                Text("Shown after a screenshot is copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Hotkey") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    Text(isRecordingHotkey ? "Press keys…" : hotkeyDisplay)
                        .foregroundStyle(isRecordingHotkey ? .secondary : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isRecordingHotkey ? Color.accentColor : Color.clear, lineWidth: 2)
                        )

                    Button(isRecordingHotkey ? "Cancel" : "Record") {
                        if isRecordingHotkey {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                }

                Text("Default is ⌘⇧6. The hotkey works while Scratio is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ScreenshotCaptureService.screenRecordingRestartHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset to Default") {
                    AppPreferences.hotkeyKeyCode = AppPreferences.defaultHotkeyKeyCode
                    AppPreferences.hotkeyModifiers = AppPreferences.defaultHotkeyModifiers
                    refreshHotkey()
                    reregister()
                }
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    Text(ScreenshotCaptureService.hasScreenCaptureAccess() ? "Granted" : "Not Granted")
                        .foregroundStyle(
                            ScreenshotCaptureService.hasScreenCaptureAccess() ? .green : .orange
                        )
                }

                Button("Open Screen Recording Settings") {
                    ScreenshotCaptureService.openScreenRecordingSettings()
                }

                Button("Request Permission") {
                    appState.requestScreenRecordingPermission()
                }
            }

            Section("Storage") {
                LabeledContent("Screenshots Folder") {
                    Text(appState.screenshotsFolderPath)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Button("Reveal in Finder") {
                    appState.revealScreenshotsFolderInFinder()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .alert("Screen Recording Required", isPresented: $appState.showPermissionAlert) {
            Button("Open System Settings") {
                ScreenshotCaptureService.openScreenRecordingSettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.permissionAlertMessage)
        }
        .task {
            appState.refreshScreenRecordingPermission()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecordingHotkey = true
        // Carbon hotkeys still fire while recording unless unregistered.
        HotkeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { return event }

            let keyCode = UInt32(event.keyCode)
            // Ignore lone modifier key presses
            if keyCode == UInt32(kVK_Command) || keyCode == UInt32(kVK_Shift)
                || keyCode == UInt32(kVK_Option) || keyCode == UInt32(kVK_Control) {
                return nil
            }

            let carbonMods = HotkeyManager.carbonModifiers(from: flags)
            AppPreferences.hotkeyKeyCode = keyCode
            AppPreferences.hotkeyModifiers = carbonMods
            refreshHotkey()
            reregister()
            stopRecording(reregisterIfNeeded: false)
            return nil
        }
    }

    private func stopRecording(reregisterIfNeeded: Bool = true) {
        isRecordingHotkey = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if reregisterIfNeeded {
            reregister()
        }
    }

    private func refreshHotkey() {
        hotkeyDisplay = HotkeyManager.displayString(
            keyCode: AppPreferences.hotkeyKeyCode,
            modifiers: AppPreferences.hotkeyModifiers
        )
    }

    private func reregister() {
        HotkeyManager.shared.reregisterFromPreferences {
            AppState.shared.startCapture()
        }
    }
}
