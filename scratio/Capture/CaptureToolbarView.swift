import SwiftUI

struct CaptureToolbarView: View {
    @Bindable var session: CaptureSessionState

    private static let controlHeight: CGFloat = 36
    private static let controlCorner: CGFloat = 7
    private static let quickAspectRatios: [AspectRatioOption] = [
        .oneToOne,
        .sixteenToNine,
        .nineToSixteen
    ]

    var body: some View {
        scratioGlassContainer(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: Self.controlHeight)
                    .contentShape(Rectangle())
                    .help("Drag to move toolbar")
                    .appKitTooltip("Drag to move toolbar")

                segmentTrack {
                    modeButton(.window)
                    modeButton(.display)
                    modeButton(.selection)
                }

                Divider()
                    .frame(height: Self.controlHeight - 4)

                segmentTrack {
                    ForEach(Self.quickAspectRatios) { option in
                        aspectRatioQuickToggle(option)
                    }
                }

                AspectRatioMenu(
                    selection: Binding(
                        get: { session.aspectRatio },
                        set: { session.setAspectRatio($0) }
                    ),
                    labelStyle: .compact
                )
                .help("Aspect ratio")
                .appKitTooltip("Aspect ratio")

                Spacer().frame(width: 8)

                Button {
                    session.onRequestCapture?()
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Capture")
                .appKitTooltip("Capture")

                Button {
                    session.onCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
                .appKitTooltip("Cancel (Esc)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .scratioGlassBackground(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        }
    }

    private func segmentTrack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func modeButton(_ mode: CaptureMode) -> some View {
        let isSelected = session.mode == mode
        let shape = RoundedRectangle(cornerRadius: Self.controlCorner, style: .continuous)
        Button {
            session.setMode(mode)
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.85))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(
                    isSelected ? Color.white.opacity(0.2) : Color.clear,
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .appKitTooltip(mode.title)
    }

    @ViewBuilder
    private func aspectRatioQuickToggle(_ option: AspectRatioOption) -> some View {
        let isSelected = session.aspectRatio == option
        let shape = RoundedRectangle(cornerRadius: Self.controlCorner, style: .continuous)
        Button {
            session.setAspectRatio(option)
        } label: {
            HStack(spacing: 5) {
                AspectRatioGlyph(
                    option: option,
                    size: 14,
                    color: isSelected ? Color.accentColor : Color.white.opacity(0.85)
                )
                Text(option.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.controlHeight)
            .background(
                isSelected ? Color.white.opacity(0.2) : Color.clear,
                in: shape
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(option.displayName)
        .appKitTooltip(option.displayName)
    }
}
