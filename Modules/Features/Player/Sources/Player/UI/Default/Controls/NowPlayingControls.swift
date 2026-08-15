//
//  NowPlayingControls.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import SwiftUI

struct NowPlayingControls: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    let size: CGSize
    let safeArea: EdgeInsets

    var body: some View {
        VStack {
            NowPlayingProgressSection()

            Spacer(minLength: 0)

            HStack(spacing: size.width * 0.18) {
                PreviousButton()
                    .sensoryFeedback(.impact, trigger: playerViewModel.currentVideoId)

                TogglePlayPauseButton()
                    .disabled(playerViewModel.currentVideoId == nil)
                    .sensoryFeedback(.selection, trigger: playerViewModel.isPlaying)

                ForwardButton()
                    .sensoryFeedback(.impact, trigger: playerViewModel.currentVideoId)
            }
            .foregroundColor(.white)

            Spacer(minLength: 0)

            VolumeSlider()
                .frame(height: 30)

            Spacer(minLength: 0)

            NowPlayingFooter(size: size, safeArea: safeArea)
        }
    }
}
#endif
