import AppKit
import SwiftUI

struct GalleryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(selection: $appState.selectedScreenshotIDs) {
                Section("Library") {
                    ForEach(appState.filteredScreenshots) { shot in
                        Text(shot.createdAt.scratioSidebarLabel())
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
            .onChange(of: appState.selectedScreenshotIDs) { _, newValue in
                if let last = appState.lastSelectedScreenshotID, newValue.contains(last) {
                    return
                }
                appState.lastSelectedScreenshotID = newValue.first
            }
        } detail: {
            VStack(spacing: 0) {
                if appState.needsScreenRecordingPermission {
                    permissionBanner
                }
                toolbar
                Divider()
                if appState.filteredScreenshots.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .navigationTitle("Captzo")
        .alert("Screen Recording Required", isPresented: $appState.showPermissionAlert) {
            Button("Open System Settings") {
                ScreenshotCaptureService.openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appState.permissionAlertMessage)
        }
        .alert(
            "Delete \(appState.selectedScreenshotIDs.count) Screenshots?",
            isPresented: $appState.showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .task {
            await appState.reloadScreenshots()
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
                Text(
                    "Without this permission the capture overlay cannot work. "
                        + "Enable Captzo in System Settings → Privacy & Security → Screen Recording, "
                        + "then quit and relaunch Captzo."
                )
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
        @Bindable var appState = appState

        return HStack(spacing: 12) {
            Picker("Sort", selection: $appState.sortOrder) {
                ForEach(GallerySortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            AspectRatioFilterMenu(filter: $appState.aspectRatioFilter)

            Spacer()

            if !appState.selectedScreenshotIDs.isEmpty {
                Button {
                    appState.copySelectedToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }

                Button {
                    appState.revealSelectedInFinder()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button(role: .destructive) {
                    if appState.selectedScreenshotIDs.count > 1 {
                        appState.showDeleteConfirmation = true
                    } else {
                        appState.deleteSelected()
                    }
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
                ForEach(appState.filteredScreenshots) { shot in
                    ScreenshotThumbnail(
                        screenshot: shot,
                        isSelected: appState.selectedScreenshotIDs.contains(shot.id),
                        badgeColorRevision: appState.badgeColorRevision
                    )
                    .onTapGesture(count: 2) {
                        appState.openInDefaultApp(shot)
                    }
                    .onTapGesture(count: 1) {
                        appState.handleGridClick(shot, flags: NSEvent.modifierFlags)
                    }
                    .contextMenu {
                        contextMenu(for: shot)
                    }
                }
            }
            .padding(20)

            if let selected = appState.primarySelectedScreenshot {
                ScreenshotPreviewPanel(
                    screenshot: selected,
                    badgeColorRevision: appState.badgeColorRevision
                )
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for shot: CapturedScreenshot) -> some View {
        let targets: [CapturedScreenshot] = {
            if appState.selectedScreenshotIDs.contains(shot.id),
               appState.selectedScreenshotIDs.count > 1 {
                return appState.selectedScreenshots
            }
            return [shot]
        }()

        Button("Open") {
            if targets.count == 1, let only = targets.first {
                appState.openInDefaultApp(only)
            } else {
                for item in targets {
                    appState.openInDefaultApp(item)
                }
            }
        }

        Button("Copy to Clipboard") {
            if let primary = targets.last {
                appState.copyToClipboard(primary)
            }
        }

        Button("Reveal in Finder") {
            appState.revealInFinder(targets)
        }

        Divider()

        Button("Delete", role: .destructive) {
            let ids = Set(targets.map(\.id))
            if ids.count > 1 {
                appState.selectedScreenshotIDs = ids
                appState.showDeleteConfirmation = true
            } else {
                appState.delete(ids: ids)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                appState.screenshots.isEmpty ? "No Screenshots Yet" : "No Matching Screenshots",
                systemImage: "camera.viewfinder"
            )
        } description: {
            if appState.screenshots.isEmpty {
                Text("Capture with a preset aspect ratio from the menu bar, or start one here.")
            } else {
                Text("Try a different aspect ratio filter.")
            }
        } actions: {
            if appState.screenshots.isEmpty {
                Button("New Capture") {
                    appState.startCapture()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Clear Filter") {
                    appState.aspectRatioFilter = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScreenshotPreviewPanel: View {
    let screenshot: CapturedScreenshot
    var badgeColorRevision: Int

    @State private var previewImage: NSImage?

    var body: some View {
        Group {
            if let previewImage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                    HStack(spacing: 8) {
                        Text("\(Int(previewImage.size.width)) × \(Int(previewImage.size.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AspectRatioBadge(
                            label: screenshot.aspectRatioLabel,
                            option: screenshot.aspectRatioOption
                        )
                        .id(badgeColorRevision)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task(id: screenshot.id) {
            previewImage = await ScreenshotStore.shared.loadImage(for: screenshot)
        }
    }
}
