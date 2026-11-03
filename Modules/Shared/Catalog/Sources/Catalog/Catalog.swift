//
//  Catalog.swift
//  Catalog
//
//  Everything known about an artist, an album or a playlist, from every source that needs no
//  sign-in: YouTube Music for the page itself (songs, releases, videos, playlists, similar
//  artists) and Apple's public iTunes catalog for the full discography, release years, genres and
//  large square artwork. Neither depends on the user being signed in to anything.
//

import Foundation
import iTunesKit
import Utilities
import YouTubeSDK

// MARK: - Values

public struct CatalogTrack: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let durationSeconds: TimeInterval?
    public let isExplicit: Bool
    /// The YouTube video that plays it.
    public let youtubeVideoID: String
    /// An official music video rather than the album audio.
    public let isMusicVideo: Bool
}

public struct CatalogAlbum: Identifiable, Sendable, Hashable {
    public var id: String { youtubeBrowseID ?? itunesCollectionID.map { "itunes:\($0)" } ?? title }
    public let title: String
    public var artist: String?
    public var year: String?
    public var genre: String?
    public var artworkURL: URL?
    /// Opens the album's tracks on YouTube Music.
    public var youtubeBrowseID: String?
    public var itunesCollectionID: Int?
}

public struct CatalogPlaylist: Identifiable, Sendable, Hashable {
    public var id: String { youtubeBrowseID }
    public let title: String
    public let owner: String?
    public let artworkURL: URL?
    public let youtubeBrowseID: String
}

public struct CatalogArtistSummary: Identifiable, Sendable, Hashable {
    public var id: String { youtubeBrowseID }
    public let name: String
    public let photoURL: URL?
    public let audience: String?
    public let youtubeBrowseID: String
}

public struct CatalogArtist: Sendable {
    public let name: String
    public let youtubeBrowseID: String?
    public let about: String?
    public let photoURL: URL?
    public let audience: String?
    public let genre: String?
    public let topSongs: [CatalogTrack]
    public let albums: [CatalogAlbum]
    public let singles: [CatalogAlbum]
    public let videos: [CatalogTrack]
    public let playlists: [CatalogPlaylist]
    public let similar: [CatalogArtistSummary]
}

// MARK: - Lookups

public actor Catalog {
    private let youtube: YouTubeMusicClient
    private let itunes: SearchService

    public init(youtube: YouTubeMusicClient, itunes: SearchService = SearchService()) {
        self.youtube = youtube
        self.itunes = itunes
    }

    /// The artist's page. A source that fails leaves only its own fields empty.
    ///
    /// - Parameter youtubeBrowseID: skips the name search when the artist came from YouTube.
    public func artist(named name: String, youtubeBrowseID: String? = nil) async -> CatalogArtist {
        var browseID = youtubeBrowseID
        if browseID == nil {
            let key = normalizedRankingText(name)
            browseID = try? await youtube.searchArtists(name).first { normalizedRankingText($0.name) == key }?.id
        }

        let resolvedID = browseID
        async let page: YouTubeMusicArtistDetail? = {
            guard let resolvedID else { return nil }
            return try? await youtube.getArtist(browseId: resolvedID)
        }()
        async let itunesPage = itunesArtist(named: name)
        let (detail, apple) = await (page, itunesPage)

        func items(_ prefix: String) -> [YouTubeMusicItem] {
            detail?.sections.filter { $0.title.hasPrefix(prefix) }.flatMap(\.items) ?? []
        }
        func tracks(_ prefix: String) -> [CatalogTrack] {
            items(prefix).compactMap { if case let .song(song) = $0 { CatalogTrack(song) } else { nil } }
        }
        func releases(_ prefix: String) -> [CatalogAlbum] {
            items(prefix).compactMap { if case let .album(album) = $0 { CatalogAlbum(album, artist: name) } else { nil } }
        }

        let merged = Self.merge(
            albums: releases("Albums"), singles: releases("Singles"),
            itunes: apple?.releases ?? []
        )

        return CatalogArtist(
            name: detail?.name ?? name,
            youtubeBrowseID: browseID,
            about: detail?.about,
            photoURL: detail?.photoURL ?? apple?.releases.first?.artworkURL,
            audience: detail?.audience,
            genre: apple?.genre,
            topSongs: tracks("Top songs"),
            albums: merged.albums,
            singles: merged.singles,
            videos: tracks("Videos"),
            playlists: (items("Playlists") + items("Featured on")).compactMap {
                if case let .playlist(playlist) = $0 { CatalogPlaylist(playlist) } else { nil }
            },
            similar: items("Fans might also like").compactMap {
                if case let .artist(artist) = $0 { CatalogArtistSummary(artist) } else { nil }
            }
        )
    }

    /// A YouTube Music playlist's tracks.
    public func playlistTracks(youtubeBrowseID: String) async -> [CatalogTrack] {
        ((try? await youtube.getPlaylist(browseId: youtubeBrowseID)) ?? []).map(CatalogTrack.init)
    }

    /// A YouTube Music album's tracks.
    public func albumTracks(youtubeBrowseID: String) async -> [CatalogTrack] {
        ((try? await youtube.getAlbum(browseId: youtubeBrowseID)) ?? []).map(CatalogTrack.init)
    }

    // MARK: iTunes

    private struct ITunesArtist {
        let genre: String?
        let releases: [ITunesRelease]
    }

    struct ITunesRelease: Sendable {
        let title: String
        let isSingle: Bool
        let year: String?
        let genre: String?
        let artworkURL: URL?
        let collectionID: Int?
    }

    private func itunesArtist(named name: String) async -> ITunesArtist? {
        let key = normalizedRankingText(name)
        guard let match = try? await itunes.search(term: name, media: "music", entity: "musicArtist", limit: 5)
            .results.first(where: { normalizedRankingText($0.artistName ?? "") == key }),
            let artistID = match.artistId,
            let lookup = try? await itunes.lookup(id: String(artistID), entity: "album", limit: 200)
        else { return nil }

        let releases = lookup.results
            .filter { $0.wrapperType == "collection" }
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            .compactMap(ITunesRelease.init)
        return ITunesArtist(genre: match.primaryGenreName, releases: releases)
    }

    // MARK: Merge

    /// YouTube's releases, in YouTube's order, filled in from iTunes (year, genre, the larger
    /// square artwork); then every iTunes release YouTube's shelves left out, newest first.
    /// iTunes marks singles and EPs in the name (" - Single", " - EP"), which also sorts them.
    static func merge(albums: [CatalogAlbum], singles: [CatalogAlbum], itunes: [ITunesRelease])
        -> (albums: [CatalogAlbum], singles: [CatalogAlbum])
    {
        var unmatched = itunes
        func fill(_ release: CatalogAlbum) -> CatalogAlbum {
            let key = normalizedRankingText(release.title)
            guard let index = unmatched.firstIndex(where: { normalizedRankingText($0.title) == key }) else { return release }
            let apple = unmatched.remove(at: index)
            var filled = release
            filled.year = filled.year ?? apple.year
            filled.genre = apple.genre
            filled.artworkURL = apple.artworkURL ?? filled.artworkURL
            filled.itunesCollectionID = apple.collectionID
            return filled
        }
        let filledAlbums = albums.map(fill)
        let filledSingles = singles.map(fill)
        func extra(_ wantSingles: Bool) -> [CatalogAlbum] {
            unmatched.filter { $0.isSingle == wantSingles }.map {
                CatalogAlbum(title: $0.title, year: $0.year, genre: $0.genre, artworkURL: $0.artworkURL, itunesCollectionID: $0.collectionID)
            }
        }
        return (filledAlbums + extra(false), filledSingles + extra(true))
    }
}

// MARK: - Mapping

extension CatalogTrack {
    init(_ song: YouTubeMusicSong) {
        self.init(
            id: song.videoId, title: song.title, artist: song.artists.joined(separator: ", "), album: song.album,
            artworkURL: song.thumbnailURL, durationSeconds: song.duration, isExplicit: song.isExplicit,
            youtubeVideoID: song.videoId, isMusicVideo: song.videoType == .musicVideo
        )
    }
}

extension CatalogAlbum {
    init(_ album: YouTubeMusicAlbum, artist: String) {
        self.init(title: album.title, artist: album.artist ?? artist, year: album.year, artworkURL: album.thumbnailURL, youtubeBrowseID: album.id)
    }
}

extension CatalogPlaylist {
    init(_ playlist: YouTubeMusicPlaylist) {
        self.init(title: playlist.title, owner: playlist.author, artworkURL: playlist.thumbnailURL, youtubeBrowseID: playlist.id)
    }
}

extension CatalogArtistSummary {
    init(_ artist: YouTubeMusicArtist) {
        self.init(name: artist.name, photoURL: artist.thumbnailURL, audience: artist.subscriberCount, youtubeBrowseID: artist.id)
    }
}

extension Catalog.ITunesRelease {
    init?(_ result: iTunesSearchResult) {
        guard let raw = result.collectionName else { return nil }
        let isSingle = raw.hasSuffix(" - Single") || raw.hasSuffix(" - EP")
        let title = isSingle ? String(raw[..<raw.range(of: " - ", options: .backwards)!.lowerBound]) : raw
        self.init(
            title: title,
            isSingle: isSingle,
            year: result.releaseDate.map { String($0.prefix(4)) },
            genre: result.primaryGenreName,
            // The API hands out 100px artwork; the same URL serves any size.
            artworkURL: result.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")) },
            collectionID: result.collectionId
        )
    }
}
