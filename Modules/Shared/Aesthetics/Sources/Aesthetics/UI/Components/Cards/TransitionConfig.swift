import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif


@MainActor
struct TransitionConfig {
    var cardCornerRadius: CGFloat = 0
#if os(iOS)
    var detailCornerRadius: CGFloat = UIScreen.deviceCornerRadius
    var detailCardHeight: CGFloat = UIScreen.main.bounds.width + 50
#elseif os(macOS)
    var detailCornerRadius: CGFloat = 24
    var detailCardHeight: CGFloat = (NSScreen.main?.frame.width ?? 0) + 50
#endif

    var animation: Animation = .smooth(duration: 0.3, extraBounce: 0)
}
