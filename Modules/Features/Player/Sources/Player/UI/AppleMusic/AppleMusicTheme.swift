//
//  AppleMusicTheme.swift
//  Player
//
//  Layout and proportions follow AppleMusicStylePlayer by Alexey Vorobyov (MIT, © 2025).
//  https://github.com/f728743/AppleMusicStylePlayer — full text in THIRD_PARTY_LICENSES.md
//
//  The composition is rewritten against cisum's PlayerViewModel rather than copied, because the
//  original binds to its own NowPlayingController and MediaLibrary types. The imported files —
//  the Metal gradient background, ElasticSlider, MarqueeText — are the parts that carry the look
//  and are used as-is.
//

#if os(iOS)
import Aesthetics
import SwiftUI

/// Album art on a colour wash drawn from the artwork.
public struct AppleMusicPlayerTheme: PlayerTheme {
    public init() {}

    public func background(
        expanded: Bool,
        fullyExpanded _: Bool,
        collapsedHeight _: CGFloat
    ) -> some View {
        AppleMusicBackground(expanded: expanded)
    }

    public func miniPlayer(expanded: Binding<Bool>, namespace: Namespace.ID) -> some View {
        AppleMusicCompactPlayer(isPlayerExpanded: expanded, namespace: namespace)
    }

    public func expanded(expanded: Bool, size: CGSize, namespace: Namespace.ID) -> some View {
        AppleMusicExpandedPlayer(
            isPlayerExpanded: expanded,
            size: size,
            namespace: namespace
        )
    }
}
#endif
