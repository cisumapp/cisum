//
//  DiscoverView.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import Aesthetics
import Kingfisher
import Models
import Player
import SwiftUI
import Tracks
import Utilities
import YouTubeSDK

public struct DiscoverView: View {
    @Environment(\.youtube) private var youtube

    public init() {}

    @State private var sections: [DiscoverSection] = []
    @State private var isLoading: Bool = false
    @State private var didLoadInitialSections: Bool = false
    @State private var errorMessage: String?
    @State private var scrollOffset: CGFloat = 0

    public var body: some View {
        NavigationBarView(
            title: "Discover",
            scrollOffset: $scrollOffset,
            customActions: [
                ProfileMenuCustomAction(title: "Change Region") {
                    // TODO: Implement Region Change
                    PerfLog.debug("Change Region selected")
                },
            ]
        ) {
            content
        }
    }

    var content: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if isLoading, sections.isEmpty {
                ProgressView("Loading Charts...")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let errorMessage, sections.isEmpty {
                ContentUnavailableView(
                    "Unable to Load Discover",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text(errorMessage)
                )

                Button("Retry") {
                    Task {
                        await loadDiscoverSections(force: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(sections) { section in
                DiscoverSectionView(section: section)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 120)
        .contentMargins(.top, 140)
        .task {
            if let cached = await DiscoverCache.load() {
                sections = cached.sections
                didLoadInitialSections = true
            }
            if !didLoadInitialSections {
                await loadDiscoverSections()
            }
        }
        .refreshable {
            await loadDiscoverSections(force: true)
        }
    }

    @MainActor
    private func loadDiscoverSections(force: Bool = false) async {
        if isLoading { return }
        if didLoadInitialSections, !force { return }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoadInitialSections = true
        }

        let countryCode = Utilities.resolvedMusicRegionCode()

        async let songsTask = youtube.charts.getTopSongs(country: countryCode)
        async let videosTask = youtube.charts.getTopVideos(country: countryCode)
        async let artistsTask = youtube.charts.getTopArtists(country: countryCode)
        async let trendingTask = youtube.charts.getTrending(country: countryCode)

        var loadedSections: [DiscoverSection] = []
        var lastError: Error?

        do {
            let songs = try await songsTask
            if !songs.isEmpty {
                loadedSections.append(
                    .init(
                        id: "songs", title: "Top Songs", subtitle: "YouTube Music",
                        items: Array(songs.prefix(10))
                    )
                )
            }
        } catch {
            lastError = error
        }

        do {
            let videos = try await videosTask
            if !videos.isEmpty {
                loadedSections.append(
                    .init(
                        id: "videos", title: "Top Videos", subtitle: "YouTube",
                        items: Array(videos.prefix(10))
                    )
                )
            }
        } catch {
            lastError = error
        }

        do {
            let artists = try await artistsTask
            if !artists.isEmpty {
                loadedSections.append(
                    .init(
                        id: "artists", title: "Top Artists", subtitle: "YouTube Music",
                        items: Array(artists.prefix(10))
                    )
                )
            }
        } catch {
            lastError = error
        }

        do {
            let trending = try await trendingTask
            if !trending.isEmpty {
                loadedSections.append(
                    .init(
                        id: "trending", title: "Trending", subtitle: "YouTube",
                        items: Array(trending.prefix(10))
                    )
                )
            }
        } catch {
            lastError = error
        }

        sections = loadedSections
        if loadedSections.isEmpty {
            errorMessage = lastError?.localizedDescription ?? "No chart data was returned."
        } else {
            DiscoverCache(sections: loadedSections, timestamp: Date()).save()
        }
    }
}

private struct DiscoverCache: Codable {
    let sections: [DiscoverSection]
    let timestamp: Date

    static var cacheFileURL: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cisum_discover_cache.json")
    }

    static func load() async -> DiscoverCache? {
        await Task.detached {
            guard let data = try? Data(contentsOf: cacheFileURL) else { return nil }
            return try? JSONDecoder().decode(DiscoverCache.self, from: data)
        }.value
    }

    func save() {
        Task.detached { [self] in
            if let data = try? JSONEncoder().encode(self) {
                try? data.write(to: Self.cacheFileURL)
            }
        }
    }
}

private struct DiscoverSection: Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let items: [YouTubeChartItem]
}

private struct DiscoverSectionView: View {
    let section: DiscoverSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                let itemsWithRank = Array(zip(section.items.indices, section.items))
                ForEach(itemsWithRank, id: \.1.id) { index, item in
                    DiscoverChartRow(rank: index + 1, item: item)
                }
            }
        }
    }
}

private struct DiscoverChartRow: View {
    let rank: Int
    let item: YouTubeChartItem

    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.router) private var router

    var body: some View {
        Button {
            playItem(item)
        } label: {
            HStack(spacing: 0) {
                Text("#\(rank)")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .padding(.leading)

                TrackListItem(
                    trackName: item.title,
                    artistName: item.subtitle,
                    artworkURL: item.thumbnailURL
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func playItem(_ item: YouTubeChartItem) {
        if item.type == .song || item.type == .video {
            let song = YouTubeMusicSong(
                id: item.id,
                title: item.title,
                artists: [item.subtitle],
                album: nil,
                duration: nil,
                thumbnailURL: item.thumbnailURL,
                videoId: item.id,
                isExplicit: false
            )
            playerViewModel.load(song: song, preserveQueue: false)
            playerPresentationController.expand()
        } else if item.type == .artist {
            router.navigate(to: .artist(id: item.id))
        }
    }
}

#Preview {
    DiscoverView()
}
