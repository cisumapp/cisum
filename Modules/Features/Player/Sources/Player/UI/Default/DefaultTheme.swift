//
//  DefaultTheme.swift
//  Player
//

#if os(iOS)
import SwiftUI

/// cisum's own player: a spinning record, with the previous and next tracks either side.
///
/// This theme is a thin wrapper. Every view it returns already existed and is unchanged — the
/// theme only names them, which is what makes the protocol trustworthy: if wrapping the existing
/// player had required editing it, the boundary would have been in the wrong place.
///
/// The Animated Artwork theme is this one with the looping video in the record's place: the
/// controls, queue and lyrics are the same, only the background differs.
public struct DefaultPlayerTheme: PlayerTheme {
    var showsMotionArtwork = false

    public init() {}

    init(showsMotionArtwork: Bool) {
        self.showsMotionArtwork = showsMotionArtwork
    }

    public func background(
        expanded: Bool,
        fullyExpanded: Bool,
        collapsedHeight: CGFloat
    ) -> some View {
        PlayerBackground(
            isPlayerExpanded: expanded,
            isFullExpanded: fullyExpanded,
            collapsedHeight: collapsedHeight,
            showsMotionArtwork: showsMotionArtwork
        )
    }

    public func miniPlayer(expanded: Binding<Bool>, namespace: Namespace.ID) -> some View {
        DynamicPlayerIsland(isPlayerExpanded: expanded, namespace: namespace)
    }

    public func expanded(expanded: Bool, size: CGSize, namespace: Namespace.ID) -> some View {
        DefaultNowPlayingView(
            isPlayerExpanded: expanded,
            size: size,
            namespace: namespace
        )
    }
}
#endif
