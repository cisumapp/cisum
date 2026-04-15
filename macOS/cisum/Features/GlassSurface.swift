import SwiftUI

struct GlassSurface: View {
    let cornerRadius: CGFloat

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .enableInjection()
    }
}

extension View {
    func cisumGlassCard(cornerRadius: CGFloat = 14) -> some View {
        background(GlassSurface(cornerRadius: cornerRadius))
    }
}
