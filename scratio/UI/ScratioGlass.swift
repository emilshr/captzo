import SwiftUI

extension View {
    @ViewBuilder
    func scratioGlassBackground<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect()
                .clipShape(shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
        }
    }
}
