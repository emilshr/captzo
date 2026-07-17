import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LanguageStore.self) private var languageStore
    @State private var hotkeyDisplay = HotkeyManager.displayString(
        keyCode: AppPreferences.hotkeyKeyCode,
        modifiers: AppPreferences.hotkeyModifiers
    )
    @State private var isRecordingHotkey = false
    @State private var monitor: Any?
    @State private var badgeColors: [AspectRatioOption: Color] = Self.loadBadgeColors()

    var body: some View {
        @Bindable var appState = appState
        let languageCode = languageStore.resolvedLanguageCode

        ScrollView {
            Form {
                Section("Language") {
                    Picker("App Language", selection: languagePreferenceBinding) {
                        ForEach(AppLanguagePreference.allCases) { option in
                            Text(pickerLabel(for: option)).tag(option)
                        }
                    }
                    .id(languageCode)
                }

                Section("Capture") {
                    LabeledContent("Default Aspect Ratio") {
                        AspectRatioMenu(
                            selection: $appState.aspectRatio,
                            labelStyle: .settings
                        )
                        .frame(maxWidth: 220)
                    }

                    Toggle("Open Gallery After Capture", isOn: $appState.openGalleryAfterCapture)
                }

                Section("Aspect Ratio Colors") {
                    ForEach(AspectRatioOption.allCases) { option in
                        HStack {
                            AspectRatioBadge(label: option.displayName, option: option)
                                .id(appState.badgeColorRevision)
                            Spacer()
                            ColorPicker(
                                "Color",
                                selection: binding(for: option),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                        }
                    }

                    Button("Reset Colors to Defaults") {
                        AppPreferences.resetBadgeColors()
                        badgeColors = Self.loadBadgeColors()
                        appState.notifyBadgeColorsChanged()
                    }
                }

                Section("Feedback") {
                    TextField(
                        L10n.tr("Copied to clipboard"),
                        text: $appState.clipboardToastMessage
                    )
                    Text("Shown after a screenshot is copied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Global Hotkey") {
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        Text(isRecordingHotkey ? L10n.tr("Press keys…") : hotkeyDisplay)
                            .foregroundStyle(isRecordingHotkey ? .secondary : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isRecordingHotkey ? Color.accentColor : Color.clear, lineWidth: 2)
                            )

                        Button(isRecordingHotkey ? L10n.tr("Cancel") : L10n.tr("Record")) {
                            if isRecordingHotkey {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }
                    }

                    Text("Default is ⌘⇧6. The hotkey works while Captzo is running.")
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
                        Text(
                            ScreenshotCaptureService.hasScreenCaptureAccess()
                                ? L10n.tr("Granted")
                                : L10n.tr("Not Granted")
                        )
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
        }
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
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

    private var languagePreferenceBinding: Binding<AppLanguagePreference> {
        Binding(
            get: { languageStore.preference },
            set: { languageStore.setPreference($0) }
        )
    }

    private func pickerLabel(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            let code = AppLanguageResolver.resolveLanguageCode(
                preference: .system,
                preferredLanguageCodes: AppLanguageResolver.preferredLanguageCodesFromSystem(),
                availableLocalizations: AppLanguageResolver.availableLocalizations()
            )
            let name = Locale.current.localizedString(forLanguageCode: code) ?? code
            return String(localized: "System (\(name))", locale: languageStore.resolvedLocale)
        default:
            return option.pickerLabel
        }
    }

    private func binding(for option: AspectRatioOption) -> Binding<Color> {
        Binding(
            get: {
                badgeColors[option] ?? option.badgeColor
            },
            set: { newColor in
                badgeColors[option] = newColor
                if let hex = newColor.hexString() {
                    AppPreferences.setBadgeColorHex(hex, for: option)
                }
                appState.notifyBadgeColorsChanged()
            }
        )
    }

    private static func loadBadgeColors() -> [AspectRatioOption: Color] {
        var result: [AspectRatioOption: Color] = [:]
        for option in AspectRatioOption.allCases {
            result[option] = option.badgeColor
        }
        return result
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
