//
//  AppleMusicExpandedPlayer.swift
//  Player
//
//  Proportions follow RegularNowPlaying and PlayerControls in AppleMusicStylePlayer
//  (MIT, © 2025 Alexey Vorobyov) — see THIRD_PARTY_LICENSES.md.
//

#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import SwiftUI
import Utilities

/// The full-screen Apple Music player: artwork, then controls under it.
struct AppleMusicExpandedPlayer: View {
    @Environment(PlayerViewModel.self) private var player

    let isPlayerExpanded: Bool
    let size: CGSize
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 12) {
            grip

            // Both the artwork and the controls are conditional, not merely faded.
            //
            // This view is crossfaded by the caller with `.opacity(isPlayerExpanded ? 1 : 0)`, so
            // while collapsed it is still in the tree. If the artwork stayed present it would be a
            // second `matchedGeometryEffect` source alongside the mini player's, SwiftUI would pick
            // one arbitrarily, and the artwork would jump instead of flying.
            if isPlayerExpanded {
                artwork
                    .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: namespace)
                    .frame(height: size.width - Const.horizontalPadding * 2)
                    // The reference tightens this on short devices so the controls still fit
                    // without scrolling.
                    .padding(.vertical, size.height < 700 ? 10 : 30)
                    .padding(.horizontal, Const.horizontalPadding)

                AppleMusicControls()
                    .transition(.move(edge: .bottom))
            }
        }
        .padding(.top, AppConstants.safeAreaInsets.top)
        .padding(.bottom, AppConstants.safeAreaInsets.bottom)
    }

    private enum Const {
        static let horizontalPadding: CGFloat = 25
    }

    private var grip: some View {
        Capsule()
            .fill(.white.secondary)
            .frame(width: 40, height: 5)
            .blendMode(.overlay)
            .opacity(isPlayerExpanded ? 1 : 0)
    }

    /// Album art that shrinks while paused — the detail that makes this player read as Apple's.
    private var artwork: some View {
        GeometryReader { proxy in
            let side = proxy.size
            let paused = !player.isPlaying

            KFImage.url(player.currentImageURL)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // Inset rather than scaled, so the corner radius stays constant instead of
                // shrinking with the image.
                .padding(paused ? 48 : 0)
                .shadow(
                    color: Color(.sRGBLinear, white: 0, opacity: paused ? 0.13 : 0.33),
                    radius: paused ? 3 : 8,
                    y: paused ? 3 : 10
                )
                .frame(width: side.width, height: side.height)
                .animation(.smooth, value: player.isPlaying)
        }
    }
}

/// Track info, scrubber, transport and volume.
struct AppleMusicControls: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let spacing = size.height * 0.04

            VStack(spacing: 0) {
                VStack(spacing: spacing) {
                    trackInfo
                    AppleMusicTimingIndicator(spacing: spacing)
                        .padding(.top, spacing)
                        .padding(.horizontal, Const.padding)
                }
                .frame(height: size.height / 2.5, alignment: .top)

                transport(spacing: size.width * 0.14)
                    .padding(.horizontal, Const.padding)

                volume(spacing: spacing)
                    .frame(height: size.height / 2.5, alignment: .bottom)
            }
        }
    }

    private enum Const {
        static let padding: CGFloat = 25
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            let config = MarqueeText.Config(leftFade: Const.padding, rightFade: Const.padding)

            MarqueeText(player.currentTitle, config: config)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                // Re-identify on change so the scroll restarts for the new title rather than
                // continuing mid-animation.
                .id(player.currentTitle)

            MarqueeText(player.currentArtist, config: config)
                .foregroundStyle(.white)
                .blendMode(.overlay)
                .id(player.currentArtist)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transport(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            PreviousButton()
                .sensoryFeedback(.impact, trigger: player.currentVideoId)

            TogglePlayPauseButton()
                .disabled(player.currentVideoId == nil)
                .sensoryFeedback(.selection, trigger: player.isPlaying)

            ForwardButton()
                .sensoryFeedback(.impact, trigger: player.currentVideoId)
        }
        .foregroundStyle(.white)
    }

    private func volume(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            VolumeSlider()
                .frame(height: 30)
                .padding(.horizontal, 8)

            NowPlayingFooter(size: .zero, safeArea: .init())
                .padding(.top, spacing)
                .padding(.horizontal, Const.padding)
        }
    }
}
#endif
