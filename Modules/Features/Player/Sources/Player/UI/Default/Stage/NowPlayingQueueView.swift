//
//  NowPlayingQueueView.swift
//  Player
//
//  Split out of NowPlayingComponents.swift, which held 12 unrelated views in 500 lines.
//  View bodies are byte-identical to before the split.
//

#if os(iOS)
import SwiftUI
import Tracks

struct NowPlayingQueueView: View {
    @Environment(PlayerViewModel.self) private var interfaceViewModel

    var body: some View {
        if let playerViewModel = interfaceViewModel as PlayerViewModel? {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(playerViewModel.queuePreviewItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playerViewModel.playQueueEntry(at: index)
                        } label: {
                            TrackListItem(
                                trackName: item.title,
                                artistName: item.subtitle,
                                duration: "",
                                artworkURL: item.artworkURL,
                                isExplicit: false
                            )
                            .background(
                                playerViewModel.currentQueuePreviewIndex == index
                                    ? Color.primary.opacity(0.15)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Color.clear
        }
    }
}
#endif
