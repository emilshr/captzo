import SwiftUI

struct AspectRatioBadge: View {
    let label: String
    let option: AspectRatioOption?
    var showGlyph: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showGlyph, let option {
                AspectRatioGlyph(option: option, size: 11, color: foreground)
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private var color: Color {
        option?.badgeColor ?? Color(hex: "8E9AAF")
    }

    private var background: Color {
        color.opacity(0.18)
    }

    private var border: Color {
        color.opacity(0.45)
    }

    private var foreground: Color {
        color
    }
}

extension CapturedScreenshot {
    var aspectRatioOption: AspectRatioOption? {
        guard let aspectRatioRaw else { return nil }
        return AspectRatioOption(rawValue: aspectRatioRaw)
    }

    var aspectRatioBadge: some View {
        AspectRatioBadge(
            label: aspectRatioLabel,
            option: aspectRatioOption
        )
    }
}
