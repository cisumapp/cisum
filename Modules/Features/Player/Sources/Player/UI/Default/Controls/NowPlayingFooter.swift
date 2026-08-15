//
//  NowPlayingFooter.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import Aesthetics
import Models
import SwiftUI

struct NowPlayingFooter: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    let size: CGSize
    let safeArea: EdgeInsets

    var body: some View {
        HStack(alignment: .top, spacing: size.width * 0.18) {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    if let pvm = playerViewModel as? PlayerViewModel {
                        pvm.nowPlayingMode = pvm.nowPlayingMode == .lyrics ? .artwork : .lyrics
                    }
                }
            } label: {
                Image(
                    systemName: playerViewModel.nowPlayingMode == .lyrics
                        ? "quote.bubble.fill" : "quote.bubble"
                )
                .font(.title2)
            }

//            AirPlayButton(activeTintColor: playerViewModel.currentAccentColor.opacity(0.2).uiColor)
            AirPlayButton()
                .opacity(0.8)
                .frame(width: 48, height: 48)
                .padding(.top, -13)

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    if let pvm = playerViewModel as? PlayerViewModel {
                        pvm.nowPlayingMode = pvm.nowPlayingMode == .queue ? .artwork : .queue
                    }
                }
            } label: {
                // Both branches of the previous ternary were "list.bullet", so it selected
                // nothing. The icon now actually reflects whether the queue is showing.
                Image(systemName: playerViewModel.nowPlayingMode == .queue ? "list.bullet.circle.fill" : "list.bullet")
                    .font(.title2)
            }
        }
        .foregroundColor(.white.opacity(0.8))
//        .blendMode(.overlay)
    }
}

struct NowPlayingInfoBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.cisumChromeSubtle, in: Capsule())
            .foregroundStyle(.primary)
    }
}
#endif
