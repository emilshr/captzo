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
            NSApp.setActivationPolicy(.regular)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            openSettings()
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
