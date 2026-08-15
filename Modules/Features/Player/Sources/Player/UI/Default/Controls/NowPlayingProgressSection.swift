//
//  NowPlayingProgressSection.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import Aesthetics
import Models
import SwiftUI

struct NowPlayingProgressSection: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    /// The playback clock, read from its own observable so the ~30Hz tick invalidates this view
    /// and nothing else. This view was already isolated for exactly that reason; the isolation
    /// only actually holds now that `currentTime` no longer arrives via the shared view model.
    @Environment(ProgressState.self) private var progress

    var body: some View {
        MusicProgressScrubber(
            mediaID: playerViewModel.currentVideoId,
            currentTime: progress.currentTime,
            duration: playerViewModel.duration,
            onSeek: { newTime in
                playerViewModel.seek(to: newTime)
            }
        )
        .frame(height: 30)
    }
}
#endif
