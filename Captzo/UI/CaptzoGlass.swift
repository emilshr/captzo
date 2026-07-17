import SwiftUI

extension View {
    @ViewBuilder
    func captzoGlassBackground<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self
                .clipShape(shape)
                .glassEffect()
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func captzoGlassContainer<Content: View>(
        spacing: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    func captzoGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func captzoGlassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
