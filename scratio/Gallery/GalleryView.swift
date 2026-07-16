import AppKit
import SwiftUI

struct GalleryView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedScreenshot?.id },
                set: { id in
                    appState.selectedScreenshot = appState.screenshots.first { $0.id == id }
                }
            )) {
                Section("Library") {
                    ForEach(appState.screenshots) { shot in
                        Text(shot.createdAt, format: .dateTime)
                            .tag(shot.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        appState.startCapture()
                    } label: {
                        Label("New Capture", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
        } detail: {
            VStack(spacing: 0) {
                if appState.needsScreenRecordingPermission {
                    permissionBanner
                }
                toolbar
                Divider()
                if appState.screenshots.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .navigationTitle("Scratio")
        .alert("Screen Recording Required", isPresented: $appState.showPermissionAlert) {
            Button("Open System Settings") {
                ScreenshotCaptureService.openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appState.permissionAlertMessage)
        }
        .onAppear {
            appState.reloadScreenshots()
            appState.refreshScreenRecordingPermission()
            NSApp.setActivationPolicy(.regular)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshScreenRecordingPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            openSettings()
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Recording permission required")
                    .font(.headline)
                Text("Without this permission the capture overlay cannot work. Enable Scratio in System Settings → Privacy & Security → Screen Recording, then quit and relaunch Scratio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Open Settings") {
                ScreenshotCaptureService.openScreenRecordingSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Check Again") {
                appState.refreshScreenRecordingPermission()
                if appState.needsScreenRecordingPermission {
                    appState.requestScreenRecordingPermission()
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("Sort", selection: $appState.sortOrder) {
                ForEach(GallerySortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            if let selected = appState.selectedScreenshot {
                Button {
                    appState.copyToClipboard(selected)
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }

                Button {
                    ScreenshotStore.shared.revealInFinder(selected)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button(role: .destructive) {
                    appState.delete(selected)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            Button {
                appState.startCapture()
            } label: {
                Label("New Capture", systemImage: "camera")
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.screenshots) { shot in
                    ScreenshotThumbnail(
                        screenshot: shot,
                        isSelected: appState.selectedScreenshot?.id == shot.id
                    )
                    .onTapGesture {
                        appState.selectedScreenshot = shot
                    }
                    .contextMenu {
                        Button("Copy to Clipboard") {
                            appState.copyToClipboard(shot)
                        }
                        Button("Reveal in Finder") {
                            ScreenshotStore.shared.revealInFinder(shot)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            appState.delete(shot)
                        }
                    }
                }
            }
            .padding(20)

            if let selected = appState.selectedScreenshot,
               let image = ScreenshotStore.shared.loadImage(for: selected) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) · \(selected.aspectRatioLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Screenshots Yet", systemImage: "camera.viewfinder")
        } description: {
            Text("Capture with a preset aspect ratio from the menu bar, or start one here.")
        } actions: {
            Button("New Capture") {
                appState.startCapture()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
