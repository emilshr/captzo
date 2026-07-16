import SwiftUI

struct CaptureToolbarView: View {
    @Bindable var session: CaptureSessionState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .help("Drag to move toolbar")
                .appKitTooltip("Drag to move toolbar")

            modeButton(.window)
            modeButton(.display)
            modeButton(.selection)

            Divider()
                .frame(height: 28)

            Menu {
                ForEach(AspectRatioOption.allCases) { option in
                    Button {
                        session.setAspectRatio(option)
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if session.aspectRatio == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(session.aspectRatio.displayName, systemImage: "aspectratio")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .disabled(session.mode != .selection)
            .help("Aspect ratio (selection mode)")
            .appKitTooltip("Aspect ratio (selection mode)")

            Spacer().frame(width: 8)

            Button {
                session.onRequestCapture?()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: Circle())
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
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
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

    @ViewBuilder
    private func modeButton(_ mode: CaptureMode) -> some View {
        Button {
            session.setMode(mode)
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(session.mode == mode ? Color.accentColor : Color.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(
                    session.mode == mode
                        ? Color.white.opacity(0.18)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .appKitTooltip(mode.title)
    }
}
