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
        .onTapGesture { isPlayerExpanded = true }
    }

    private var artwork: some View {
        KFImage.url(player.currentImageURL)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
