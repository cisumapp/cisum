import Aesthetics
import Models
import Player
import SwiftData
import SwiftUI
import Tracks
import Utilities
import YouTubeSDK

public struct HomeView: View {
    @Environment(\.router) private var router
    @State private var viewModel: HomeViewModel

    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(\.searchViewModel) private var searchViewModel
    @Environment(PlayerPresentationController.self) private var playerPresentationController

    @Query(sort: \ListeningHistoryEntry.startedAt, order: .reverse) private var recentHistory: [ListeningHistoryEntry]

    @State private var scrollOffset: CGFloat = 0

    @State private var uniqueHistoryItemsWithDisplay: [HomeFeedItemWithDisplay] = []

    private func updateUniqueHistoryItems() {
        var seenMediaIDs = Set<String>()
        uniqueHistoryItemsWithDisplay = recentHistory
            .filter { entry in
                seenMediaIDs.insert(entry.mediaID).inserted
            }
            .prefix(15)
            .map { entry in
                let item = entry.asHomeFeedItem
                return .init(item: item, display: item.displayItem())
            }
    }

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationBarView(title: "Home", scrollOffset: $scrollOffset) {
            content
        }
    }

    var content: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView("Loading Home Feed...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                    .tint(.primary)
            }

            if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Unable to Load Home",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .foregroundStyle(.primary)

                Button("Retry") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            // Horizontal Sections
            if !uniqueHistoryItemsWithDisplay.isEmpty {
                HorizontalTrackSection(title: "Jump Back In", items: uniqueHistoryItemsWithDisplay, onPlay: playItem)
            }

            if !viewModel.topSongsWithDisplay.isEmpty {
                HorizontalTrackSection(title: "Top Songs", items: viewModel.topSongsWithDisplay, onPlay: playItem)
            }

            if !viewModel.trendingWithDisplay.isEmpty {
                HorizontalTrackSection(title: "Trending", items: viewModel.trendingWithDisplay, onPlay: playItem)
            }

            // Vertical generic recommendations
            if !viewModel.items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended for You")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.displayItems) { wrapped in
                            Button {
                                playItem(wrapped.item)
                            } label: {
                                TrackCard(
                                    trackName: wrapped.display.title,
                                    artistName: wrapped.display.subtitle,
                                    duration: wrapped.display.duration ?? "",
                                    artworkURL: wrapped.display.artworkURL,
                                    artworkColor: .cisumAccent
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentItem: wrapped.item)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if viewModel.isLoadingMore {
                ProgressView("Loading More...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .tint(.primary)
            }

            if let footerMessage = viewModel.footerMessage, !viewModel.items.isEmpty {
                Text(footerMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 120)
        .padding(.top, 16)
        .task {
            updateUniqueHistoryItems()
            await viewModel.loadIfNeeded()
        }
        .onChange(of: recentHistory.count) { _, _ in
            updateUniqueHistoryItems()
        }
        .pullToRefresh(scrollOffset: scrollOffset) {
            await viewModel.refresh()
        }
    }

    private func playItem(_ item: HomeFeedItem) {
        switch item {
        case let .musicSong(song):
            searchViewModel?.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(song: song, preserveQueue: false)
            playerPresentationController.expand()
        case let .main(.song(song)):
            searchViewModel?.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(song: song, preserveQueue: false)
            playerPresentationController.expand()
        case let .main(.video(video)):
            searchViewModel?.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(video: video, preserveQueue: false)
            playerPresentationController.expand()
        case let .musicPlaylist(playlist):
            router.navigate(to: .playlist(id: playlist.id))
        case let .main(.playlist(playlist)):
            router.navigate(to: .playlist(id: playlist.id))
        case let .musicAlbum(album):
            router.navigate(to: .album(id: album.id))
        case let .musicArtist(artist):
            router.navigate(to: .artist(id: artist.id))
        default:
            break
        }
    }
}

// MARK: - Subviews & Extensions

private struct HorizontalTrackSection: View {
    let title: String
    let items: [HomeFeedItemWithDisplay]
    let onPlay: (HomeFeedItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { wrapped in
                        Button {
                            onPlay(wrapped.item)
                        } label: {
                            TrackCard(
                                trackName: wrapped.display.title,
                                artistName: wrapped.display.subtitle,
                                duration: wrapped.display.duration ?? "",
                                artworkURL: wrapped.display.artworkURL,
                                artworkColor: .cisumAccent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

extension ListeningHistoryEntry {
    var asHomeFeedItem: HomeFeedItem {
        let song = YouTubeMusicSong(
            id: mediaID,
            title: title,
            artists: [artist],
            album: album,
            duration: nil,
            thumbnailURL: artworkURL.flatMap { URL(string: $0) },
            videoId: mediaID,
            isExplicit: false
        )
        return .musicSong(song)
    }
}
