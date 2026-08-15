//
//  DefaultNowPlayingView.swift
//  Player
//
//  cisum's own now-playing layout: the vinyl theme.
//
//  Renamed from NowPlayingView and moved here as the first player theme. Layout, spacing and
//  every child view are unchanged — the differences from the original are that `import Models`
//  no longer sits above the file header, the stage takes a single `NowPlayingMode` instead of two
//  booleans, and a downcast of a value that was already the right type is gone.
//

#if os(iOS)
import SwiftUI
import Utilities

public struct DefaultNowPlayingView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

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

            NowPlayingArtwork(mode: playerViewModel.nowPlayingMode)

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

private extension DefaultNowPlayingView {
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
