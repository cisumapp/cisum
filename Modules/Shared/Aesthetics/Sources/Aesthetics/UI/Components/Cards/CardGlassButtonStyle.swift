import SwiftUI

extension View {
    @ViewBuilder
    func cardGlassButtonStyle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(CardGlassFallbackButtonStyle())
        }
        #else
        buttonStyle(CardGlassFallbackButtonStyle())
        #endif
    }
}

struct CardGlassFallbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(configuration.isPressed ? Color.cisumChromeSubtle : Color.cisumChromeBorder, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
