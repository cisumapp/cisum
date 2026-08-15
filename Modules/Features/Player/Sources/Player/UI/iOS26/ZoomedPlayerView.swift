//
//  ZoomedPlayerView.swift
//  Player
//

#if os(iOS)
import SwiftUI

/// The full player, as presented inside the iOS 26 zoom cover.
///
/// The same theme content `ExpandablePlayer` renders — but without any of the expansion
/// machinery around it, because inside a `fullScreenCover` the system owns all of that.
///
/// `ExpandablePlayer` cannot be reused here directly: it is built to live in the overlay window
/// and hides itself with `.opacity(isFullyCollapsed ? 0 : 1)`, where `isFullyCollapsed` derives
/// from `expandProgress` — a value the overlay's pan gesture drives. Inside a cover nothing
/// drives it, so it stays zero and the player renders invisibly. Everything else it does — the
/// pan gesture, `stacked()`, `resizeWindow`, the collapsed padding and corner radius — is
/// likewise meaningless when the system is presenting and dismissing the view.
public struct ZoomedPlayerView: View {
    @Environment(PlayerThemeSettings.self) private var themeSettings

    @Namespace private var namespace

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                PlayerThemeRenderer.background(
                    themeSettings.selected,
                    expanded: true,
                    fullyExpanded: true,
                    collapsedHeight: 0
                )

                PlayerThemeRenderer.expanded(
                    themeSettings.selected,
                    expanded: true,
                    size: proxy.size,
                    namespace: namespace
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}
#endif
