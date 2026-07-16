import SwiftUI

/// Dotted box sized to match an aspect ratio for menu rows and badges.
struct AspectRatioGlyph: View {
    let option: AspectRatioOption
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        Canvas { context, canvasSize in
            let rect = glyphRect(in: canvasSize)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            context.stroke(
                path,
                with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 2])
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func glyphRect(in canvasSize: CGSize) -> CGRect {
        let inset: CGFloat = 1.5
        let available = CGSize(
            width: canvasSize.width - inset * 2,
            height: canvasSize.height - inset * 2
        )

        guard let ratio = option.ratio else {
            // Freeform: irregular rounded rect
            return CGRect(
                x: inset + available.width * 0.1,
                y: inset + available.height * 0.15,
                width: available.width * 0.8,
                height: available.height * 0.7
            )
        }

        let fitted: CGSize
        if ratio >= 1 {
            let width = available.width
            let height = width / ratio
            if height <= available.height {
                fitted = CGSize(width: width, height: height)
            } else {
                fitted = CGSize(width: available.height * ratio, height: available.height)
            }
        } else {
            let height = available.height
            let width = height * ratio
            if width <= available.width {
                fitted = CGSize(width: width, height: height)
            } else {
                fitted = CGSize(width: available.width, height: available.width / ratio)
            }
        }

        return CGRect(
            x: inset + (available.width - fitted.width) / 2,
            y: inset + (available.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
