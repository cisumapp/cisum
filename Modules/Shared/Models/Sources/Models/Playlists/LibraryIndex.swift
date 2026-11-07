//
//  LibraryIndex.swift
//  Models
//
//  The Library's songs, albums and artists, worked out from the user's playlists.
//

import Foundation
import Utilities

/// Songs, albums and artists derived only from the tracks in the user's playlists.
///
/// Nothing is stored: the Library is whatever the user's playlists (imported, created, Saved,
/// shared) contain. That is what keeps search results and played tracks out of it — they are
/// cached elsewhere, but only a playlist puts a track here.
public struct LibraryIndex {
    public struct Song: Identifiable {
        public let id: String
        /// The playlist row that represents the song: the one playable from the most services.
        public let item: PlaylistItem
        /// When the song first entered any playlist.
        public let addedAt: Date

        public var title: String { item.title }
        public var artist: String { item.artistName ?? "" }
        public var album: String? { item.albumName.flatMap { $0.isEmpty ? nil : $0 } }
        public var artworkURL: URL? { item.artworkURLString.flatMap(URL.init(string:)) }
    }

    public struct Album: Identifiable {
        public let id: String
        public let title: String
        public let artist: String
        public let songs: [Song]
        public var artworkURL: URL? { songs.lazy.compactMap(\.artworkURL).first }
    }

    public struct Artist: Identifiable {
        public let id: String
        public let name: String
        public let songs: [Song]
        public let albums: [Album]
        public var artworkURL: URL? { songs.lazy.compactMap(\.artworkURL).first }
    }

    /// A–Z by title.
    public let songs: [Song]
    /// A–Z by title.
    public let albums: [Album]
    /// A–Z by name.
    public let artists: [Artist]

    public init(items: [PlaylistItem]) {
        // One song per title and lead artist, whichever playlist and service it came from.
        var byKey: [String: [PlaylistItem]] = [:]
        for item in items where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            byKey[Self.songKey(item), default: []].append(item)
        }
        let songs = byKey.map { key, copies in
            Song(
                id: key,
                item: copies.max { ($0.knownSources.count, $1.createdAt) < ($1.knownSources.count, $0.createdAt) }!,
                addedAt: copies.map(\.createdAt).min()!
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // ponytail: an album is its name under the lead artist, so a compilation splits per
        // artist. Group by album artist if imports ever carry one.
        let albums = Dictionary(grouping: songs.filter { $0.album != nil }) {
            Self.key($0.album!) + "|" + Self.key(Self.leadArtist($0.artist))
        }
        .map { id, songs in
            Album(id: id, title: songs[0].album!, artist: Self.leadArtist(songs[0].artist), songs: songs)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let albumsByArtist = Dictionary(grouping: albums) { Self.key($0.artist) }
        let artists = Dictionary(grouping: songs.filter { !$0.artist.isEmpty }) { Self.key(Self.leadArtist($0.artist)) }
            .map { id, songs in
                Artist(id: id, name: Self.leadArtist(songs[0].artist), songs: songs, albums: albumsByArtist[id] ?? [])
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        self.songs = songs
        self.albums = albums
        self.artists = artists
    }

    /// The first credited artist: "Calvin Harris, Dua Lipa" and "Calvin Harris feat. Dua Lipa"
    /// both belong to Calvin Harris.
    static func leadArtist(_ name: String) -> String {
        var lead = name
        for separator in [", ", " & ", " feat. ", " feat ", " ft. ", " featuring ", " with ", " x ", " × "] {
            if let range = lead.range(of: separator, options: .caseInsensitive) {
                lead = String(lead[..<range.lowerBound])
            }
        }
        return lead.trimmingCharacters(in: .whitespaces)
    }

    /// The id this index gives the artist called `name`, so an artist page can find the user's
    /// saved songs by them.
    public static func artistID(forName name: String) -> String {
        key(leadArtist(name))
    }

    static func songKey(_ item: PlaylistItem) -> String {
        key(item.title) + "|" + key(leadArtist(item.artistName ?? ""))
    }

    static func key(_ text: String) -> String {
        let normalized = normalizedRankingText(text)
        return normalized.isEmpty ? text.lowercased() : normalized
    }
}
