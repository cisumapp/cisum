import Utilities

//
//  HomeViewModel.swift
//  cisum
//
//  Created by Aarav Gupta on 29/03/26.
//

import Foundation
import Models
import Observation
import YouTubeSDK

private final class HomeFeedCache: Codable, Sendable {
    let topSongs: [HomeFeedItem]
    let trending: [HomeFeedItem]
    let items: [HomeFeedItem]
    let continuationToken: String?
    let loadedContinuationPages: Int
    let seenItemKeys: Set<String>
    let timestamp: Date

    private static let cacheFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("home_feed_cache.json")
    }()

    init(topSongs: [HomeFeedItem], trending: [HomeFeedItem], items: [HomeFeedItem], continuationToken: String?, loadedContinuationPages: Int, seenItemKeys: Set<String>, timestamp: Date) {
        self.topSongs = topSongs
        self.trending = trending
        self.items = items
        self.continuationToken = continuationToken
        self.loadedContinuationPages = loadedContinuationPages
        self.seenItemKeys = seenItemKeys
        self.timestamp = timestamp
    }

    func save() {
        Task.detached { [self] in
            guard let data = try? JSONEncoder().encode(self) else { return }
            try? data.write(to: Self.cacheFileURL, options: .atomic)
        }
    }

    static func load() async -> HomeFeedCache? {
        await Task.detached {
            guard let data = try? Data(contentsOf: cacheFileURL) else { return nil }
            return try? JSONDecoder().decode(HomeFeedCache.self, from: data)
        }.value
    }

    static func clear() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}

@Observable
@MainActor
final class HomeViewModel {
    private enum Pagination {
        static let threshold = 8
        static let maxPages = 4
        static let cooldown: TimeInterval = 0.35
    }

    private let youtube: YouTube
    private var continuationToken: String?
    private var loadedContinuationPages = 0
    private var seenItemKeys = Set<String>()
    private var lastPaginationTriggerAt: Date?
    private var lastPaginationTriggerToken: String?

    var topSongs: [HomeFeedItem] = [] {
        didSet {
            topSongsWithDisplay = topSongs.map { .init(item: $0, display: $0.displayItem()) }
        }
    }

    var trending: [HomeFeedItem] = [] {
        didSet {
            trendingWithDisplay = trending.map { .init(item: $0, display: $0.displayItem()) }
        }
    }

    var items: [HomeFeedItem] = [] {
        didSet {
            updateDisplayItems()
        }
    }

    private(set) var topSongsWithDisplay: [HomeFeedItemWithDisplay] = []
    private(set) var trendingWithDisplay: [HomeFeedItemWithDisplay] = []
    private(set) var displayItems: [HomeFeedItemWithDisplay] = []

    var isLoading = false
    var isLoadingMore = false
    var didLoadInitialFeed = false
    var errorMessage: String?
    var footerMessage: String?

    var canLoadMore: Bool {
        continuationToken != nil && loadedContinuationPages < Pagination.maxPages
    }

    init(youtube: YouTube) {
        self.youtube = youtube
    }

    private func updateDisplayItems() {
        displayItems = items.map { .init(item: $0, display: $0.displayItem()) }
    }

    func loadIfNeeded() async {
        guard !didLoadInitialFeed else { return }
        await loadInitialFeed(force: false)
    }

    func refresh() async {
        await loadInitialFeed(force: true)
    }

    func loadMoreIfNeeded(currentItem: HomeFeedItem) {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        let totalCount = items.count
        guard totalCount > 0 else { return }
        let triggerIndex = max(totalCount - Pagination.threshold, 0)
        guard currentIndex >= triggerIndex else { return }
        guard canLoadMore else {
            if loadedContinuationPages >= Pagination.maxPages {
                footerMessage = "Showing the latest music recommendations for now."
            }
            return
        }
        guard !isLoadingMore else { return }

        if let token = continuationToken,
           let lastTime = lastPaginationTriggerAt,
           lastPaginationTriggerToken == token,
           Date().timeIntervalSince(lastTime) < Pagination.cooldown
        {
            return
        }

        lastPaginationTriggerAt = Date()
        lastPaginationTriggerToken = continuationToken

        Task {
            await loadMore()
        }
    }

    private func loadInitialFeed(force: Bool) async {
        if isLoading { return }
        if didLoadInitialFeed, !force { return }

        if !force, let cache = await HomeFeedCache.load(), Date().timeIntervalSince(cache.timestamp) < 21600 {
            topSongs = cache.topSongs
            trending = cache.trending
            items = cache.items
            continuationToken = cache.continuationToken
            loadedContinuationPages = cache.loadedContinuationPages
            seenItemKeys = cache.seenItemKeys
            isLoading = false
            didLoadInitialFeed = true
            return
        }

        isLoading = true
        errorMessage = nil
        if force {
            footerMessage = nil
            loadedContinuationPages = 0
            continuationToken = nil
            seenItemKeys.removeAll(keepingCapacity: true)
            topSongs.removeAll(keepingCapacity: true)
            trending.removeAll(keepingCapacity: true)
            HomeFeedCache.clear()
        }

        defer {
            isLoading = false
            didLoadInitialFeed = true
        }

        var mergedItems: [HomeFeedItem] = []
        var latestError: Error?

        async let musicSectionsResult = fetchMusicSections()
        async let mainHomeResult = fetchMainHomeContinuation()
        async let topSongsResult = fetchTopSongs()
        async let trendingResult = fetchTrending()

        switch await musicSectionsResult {
        case let .success(musicSections):
            mergedItems.append(contentsOf: mapMusicSections(musicSections))
        case let .failure(error):
            latestError = error
        }

        switch await mainHomeResult {
        case let .success(homeContinuation):
            continuationToken = homeContinuation.continuationToken
            mergedItems.append(contentsOf: mapMainItems(homeContinuation.items))
        case let .failure(error):
            continuationToken = nil
            latestError = latestError ?? error
        }

        if case let .success(songs) = await topSongsResult {
            topSongs = songs.map(\.asHomeFeedItem)
        }

        if case let .success(trends) = await trendingResult {
            trending = trends.map(\.asHomeFeedItem)
        }

        let hasItems = mergeItems(mergedItems, replacing: true)

        if !hasItems {
            errorMessage = latestError?.localizedDescription ?? "No music items were returned from Home."
            footerMessage = nil
            return
        }

        if continuationToken == nil {
            footerMessage = "No more Home pages are available right now."
        }

        HomeFeedCache(
            topSongs: topSongs,
            trending: trending,
            items: items,
            continuationToken: continuationToken,
            loadedContinuationPages: loadedContinuationPages,
            seenItemKeys: seenItemKeys,
            timestamp: Date()
        ).save()
    }

    private func fetchMusicSections() async -> Result<[YouTubeMusicSection], Error> {
        do {
            let sections = try await youtube.music.getHome()
            return .success(sections)
        } catch {
            return .failure(error)
        }
    }

    private func fetchMainHomeContinuation() async -> Result<YouTubeContinuation<YouTubeItem>, Error> {
        do {
            let continuation = try await youtube.main.getHome()
            return .success(continuation)
        } catch {
            return .failure(error)
        }
    }

    private func fetchTopSongs() async -> Result<[YouTubeChartItem], Error> {
        do {
            let songs = try await youtube.charts.getTopSongs(country: "US")
            return .success(songs)
        } catch {
            return .failure(error)
        }
    }

    private func fetchTrending() async -> Result<[YouTubeChartItem], Error> {
        do {
            let items = try await youtube.charts.getTrending(country: "US")
            return .success(items)
        } catch {
            return .failure(error)
        }
    }

    private func loadMore() async {
        guard let token = continuationToken, !token.isEmpty else {
            footerMessage = "You're all caught up."
            return
        }
        guard loadedContinuationPages < Pagination.maxPages else {
            footerMessage = "Showing the latest music recommendations for now."
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let continuation = try await youtube.main.getHome()
            continuationToken = continuation.continuationToken
            loadedContinuationPages += 1

            let appended = mergeItems(mapMainItems(continuation.items), replacing: false)
            if !appended, continuationToken == nil {
                footerMessage = "You're all caught up."
            }

            if loadedContinuationPages >= Pagination.maxPages {
                footerMessage = "Showing the latest music recommendations for now."
            }

            HomeFeedCache(
                topSongs: topSongs,
                trending: trending,
                items: items,
                continuationToken: continuationToken,
                loadedContinuationPages: loadedContinuationPages,
                seenItemKeys: seenItemKeys,
                timestamp: Date()
            ).save()
        } catch {
            continuationToken = nil
            if items.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                footerMessage = "Unable to load more Home items right now."
            }
        }
    }

    private func mapMusicSections(_ sections: [YouTubeMusicSection]) -> [HomeFeedItem] {
        sections.flatMap(\.items).compactMap { item in
            switch item {
            case let .song(song):
                .musicSong(song)
            case let .album(album):
                .musicAlbum(album)
            case let .artist(artist):
                .musicArtist(artist)
            case let .playlist(playlist):
                .musicPlaylist(playlist)
            }
        }
    }

    private func mapMainItems(_ sourceItems: [YouTubeItem]) -> [HomeFeedItem] {
        sourceItems
            .filter { shouldKeepMusicHomeItem($0) }
            .map { HomeFeedItem.main($0) }
    }

    @discardableResult
    private func mergeItems(_ incomingItems: [HomeFeedItem], replacing: Bool) -> Bool {
        if replacing {
            items.removeAll(keepingCapacity: true)
            seenItemKeys.removeAll(keepingCapacity: true)
        }

        var appended = false
        for item in incomingItems {
            let key = item.stableKey
            if seenItemKeys.insert(key).inserted {
                items.append(item)
                appended = true
            }
        }

        return appended
    }
}

enum HomeFeedItem: Identifiable, Codable {
    case musicSong(YouTubeMusicSong)
    case musicAlbum(YouTubeMusicAlbum)
    case musicArtist(YouTubeMusicArtist)
    case musicPlaylist(YouTubeMusicPlaylist)
    case main(YouTubeItem)

    var id: String {
        stableKey
    }

    var stableKey: String {
        switch self {
        case let .musicSong(song):
            "media:\(song.videoId)"
        case let .musicAlbum(album):
            "album:\(album.id)"
        case let .musicArtist(artist):
            "artist:\(artist.id)"
        case let .musicPlaylist(playlist):
            "playlist:\(playlist.id)"
        case let .main(item):
            switch item {
            case let .video(video):
                "media:\(video.id)"
            case let .song(song):
                "media:\(song.videoId)"
            case let .playlist(playlist):
                "playlist:\(playlist.id)"
            case let .channel(channel):
                "channel:\(channel.id)"
            case let .shelf(shelf):
                "shelf:\(shelf.title.lowercased())"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum ItemType: String, Codable {
        case musicSong, musicAlbum, musicArtist, musicPlaylist, main
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .musicSong(song):
            try container.encode(ItemType.musicSong, forKey: .type)
            try container.encode(song, forKey: .payload)
        case let .musicAlbum(album):
            try container.encode(ItemType.musicAlbum, forKey: .type)
            try container.encode(album, forKey: .payload)
        case let .musicArtist(artist):
            try container.encode(ItemType.musicArtist, forKey: .type)
            try container.encode(artist, forKey: .payload)
        case let .musicPlaylist(playlist):
            try container.encode(ItemType.musicPlaylist, forKey: .type)
            try container.encode(playlist, forKey: .payload)
        case let .main(item):
            try container.encode(ItemType.main, forKey: .type)
            try container.encode(item, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .musicSong:
            self = .musicSong(try container.decode(YouTubeMusicSong.self, forKey: .payload))
        case .musicAlbum:
            self = .musicAlbum(try container.decode(YouTubeMusicAlbum.self, forKey: .payload))
        case .musicArtist:
            self = .musicArtist(try container.decode(YouTubeMusicArtist.self, forKey: .payload))
        case .musicPlaylist:
            self = .musicPlaylist(try container.decode(YouTubeMusicPlaylist.self, forKey: .payload))
        case .main:
            self = .main(try container.decode(YouTubeItem.self, forKey: .payload))
        }
    }
}

struct HomeFeedDisplayItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let artworkURL: URL?
    let duration: String?

    static func == (lhs: HomeFeedDisplayItem, rhs: HomeFeedDisplayItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

struct HomeFeedItemWithDisplay: Identifiable, Equatable {
    let item: HomeFeedItem
    let display: HomeFeedDisplayItem
    var id: String {
        item.id
    }

    static func == (lhs: HomeFeedItemWithDisplay, rhs: HomeFeedItemWithDisplay) -> Bool {
        lhs.display == rhs.display
    }
}

extension HomeFeedItem {
    func displayItem() -> HomeFeedDisplayItem {
        let title: String
        let subtitle: String
        let symbolName: String
        let artworkURL: URL?
        var formattedDuration: String?

        switch self {
        case let .musicSong(song):
            title = normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay)
            let album = song.album ?? "Single"
            subtitle = "\(normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title)) • \(album)"
            symbolName = "music.note"
            artworkURL = song.thumbnailURL
            formattedDuration = song.duration.map { Self.formatDuration($0) }

        case let .musicAlbum(album):
            title = normalizedMusicDisplayTitle(album.title, artist: album.artist)
            let artist = album.artist ?? "Album"
            if let year = album.year, !year.isEmpty {
                subtitle = "\(artist) • \(year)"
            } else {
                subtitle = artist
            }
            symbolName = "square.stack.fill"
            artworkURL = album.thumbnailURL
            formattedDuration = nil

        case let .musicArtist(artist):
            title = normalizedMusicDisplayTitle(artist.name)
            subtitle = artist.subscriberCount ?? "Artist"
            symbolName = "person.crop.square"
            artworkURL = artist.thumbnailURL
            formattedDuration = nil

        case let .musicPlaylist(playlist):
            title = normalizedMusicDisplayTitle(playlist.title, artist: playlist.author)
            let author = playlist.author ?? "Playlist"
            if let count = playlist.count, !count.isEmpty {
                subtitle = "\(author) • \(count)"
            } else {
                subtitle = author
            }
            symbolName = "music.note.list"
            artworkURL = playlist.thumbnailURL
            formattedDuration = nil

        case let .main(sourceItem):
            switch sourceItem {
            case let .video(video):
                title = normalizedMusicDisplayTitle(video.title, artist: video.author)
                subtitle = normalizedMusicDisplayArtist(video.author, title: video.title)
                symbolName = "play.rectangle.fill"
                artworkURL = video.thumbnailURL.flatMap { URL(string: $0) }
                if let secs = Double(video.lengthInSeconds) {
                    formattedDuration = Self.formatDuration(secs)
                } else {
                    formattedDuration = nil
                }

            case let .song(song):
                title = normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay)
                let album = song.album ?? "Single"
                subtitle = "\(normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title)) • \(album)"
                symbolName = "music.note"
                artworkURL = song.thumbnailURL
                formattedDuration = song.duration.map { Self.formatDuration($0) }

            case let .playlist(playlist):
                title = normalizedMusicDisplayTitle(playlist.title, artist: playlist.author)
                subtitle = playlist.author ?? "Playlist"
                symbolName = "music.note.list"
                artworkURL = playlist.thumbnailURL
                formattedDuration = nil

            case let .channel(channel):
                title = normalizedMusicDisplayTitle(channel.title)
                subtitle = channel.subscriberCount ?? "Channel"
                symbolName = "person.crop.circle"
                artworkURL = channel.thumbnailURL
                formattedDuration = nil

            case let .shelf(shelf):
                title = normalizedMusicDisplayTitle(shelf.title)
                subtitle = "\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")"
                symbolName = "square.grid.2x2.fill"
                artworkURL = nil
                formattedDuration = nil
            }
        }

        return HomeFeedDisplayItem(
            id: stableKey,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            artworkURL: artworkURL,
            duration: formattedDuration
        )
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

extension YouTubeChartItem {
    var asHomeFeedItem: HomeFeedItem {
        let song = YouTubeMusicSong(
            id: id,
            title: title,
            artists: [subtitle],
            album: nil,
            duration: nil,
            thumbnailURL: thumbnailURL,
            videoId: id,
            isExplicit: false
        )
        return .musicSong(song)
    }
}
