import Models
//
//  NowPlayingView.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

#if os(iOS)
import SwiftUI
import Utilities

public struct NowPlayingView: View {
    @Environment(\.playerViewModel) private var playerViewModel

    public var isPlayerExpanded: Bool
    public var size: CGSize
    public var namespace: Namespace.ID

    public init(isPlayerExpanded: Bool, size: CGSize, namespace: Namespace.ID) {
        self.isPlayerExpanded = isPlayerExpanded
        self.size = size
        self.namespace = namespace
    }

    public var body: some View {
        VStack(spacing: 12) {
            header

            NowPlayingArtwork(
                size: size,
                artworkURL: playerViewModel.currentImageURL,
                isLyricsVisible: playerViewModel.isLyricsVisible,
                isQueueVisible: (playerViewModel as? PlayerViewModel)?.isQueueVisible ?? false
            )

            NowPlayingSongInfo(
                title: playerViewModel.currentTitle,
                artist: playerViewModel.currentArtist,
                isExplicit: playerViewModel.isExplicit,
                videoId: playerViewModel.currentVideoId
            )

            GeometryReader { proxy in
                NowPlayingControls(size: proxy.size, safeArea: proxy.safeAreaInsets)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, AppConstants.safeAreaInsets.top)
        .padding(.bottom, AppConstants.safeAreaInsets.bottom)
    }
}

fileprivate extension NowPlayingView {
    var header: some View {
        Capsule()
            .fill(.secondary.opacity(0.55))
            .blendMode(.overlay)
            .opacity(isPlayerExpanded ? 1 : 0)
            .frame(width: 40, height: 5)
            .offset(y: 10)
    }
}
#endif
