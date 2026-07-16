import AppKit
import SwiftUI

struct ScreenshotThumbnail: View {
    let screenshot: CapturedScreenshot
    let isSelected: Bool
    var badgeColorRevision: Int = 0

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )

            Text(screenshot.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            AspectRatioBadge(
                label: screenshot.aspectRatioLabel,
                option: screenshot.aspectRatioOption
            )
            .id(badgeColorRevision)
        }
        .contentShape(Rectangle())
        .task(id: screenshot.id) {
            image = await ScreenshotStore.shared.loadImage(for: screenshot)
        }
    }
}
