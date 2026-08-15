//
//  AppleMusicCompactPlayer.swift
//  Player
//
//  Follows CompactNowPlaying in AppleMusicStylePlayer (MIT, © 2025 Alexey Vorobyov).
//

#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import SwiftUI
import Utilities

/// The collapsed pill for the Apple Music theme.
///
/// Only rendered on iOS 17/18. iOS 26 has a real `tabViewBottomAccessory` acting as the collapsed
/// player, and drawing a second one produces a visible two-layer handoff during expansion.
struct AppleMusicCompactPlayer: View {
    @Environment(PlayerViewModel.self) private var player

    @Binding var isPlayerExpanded: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            artwork

            MarqueeTitle(title: player.currentTitle)

            Spacer(minLength: 0)

            TogglePlayPauseButton()
                .disabled(player.currentVideoId == nil)

            ForwardButton()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: AppConstants.dynamicPlayerIslandHeight)
        .contentShape(.rect)
        .onTapGesture {
            // Same animation the default theme's pill uses, so expansion feels identical whichever
            // theme is selected — the flow is deliberately theme-independent.
            withAnimation(.playerExpandAnimation) {
                isPlayerExpanded = true
            }
        }
    }

    /// The artwork that flies up into the expanded player.
    ///
    /// Removed from the tree entirely once expanded, rather than hidden. `matchedGeometryEffect`
    /// pairs by `(id, namespace)` and tolerates only one source at a time; leaving this in place
    /// with `.opacity(0)` would give SwiftUI two and it would pick one arbitrarily, which shows up
    /// as the artwork jumping instead of flying.
    @ViewBuilder
    private var artwork: some View {
        if !isPlayerExpanded {
            KFImage.url(player.currentImageURL)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: namespace)
        }
    }
}

/// Wraps the title so the marquee re-identifies on track change and restarts its scroll, rather
/// than continuing mid-animation with new text.
private struct MarqueeTitle: View {
    let title: String

    var body: some View {
        MarqueeText(title, config: .init(leftFade: 8, rightFade: 8))
            .font(.subheadline.weight(.medium))
            .id(title)
    }
}
#endif
