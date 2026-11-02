//
//  LibraryIndexTests.swift
//  ModelsTests
//

import Foundation
@testable import Models
import Testing

private func item(
    _ title: String,
    _ artist: String?,
    album: String? = nil,
    playlist: String = "p",
    index: Int = 0,
    youtube: String? = nil,
    spotify: String? = nil,
    added: TimeInterval = 0
) -> PlaylistItem {
    PlaylistItem(
        playlistID: playlist,
        sortIndex: index,
        sourceTrackFingerprint: "\(title)-\(artist ?? "")",
        title: title,
        artistName: artist,
        albumName: album,
        youtubeID: youtube,
        spotifyID: spotify,
        createdAt: Date(timeIntervalSince1970: added)
    )
}

@Suite("Library index")
struct LibraryIndexTests {
    @Test("the same song in two playlists is one song, kept as the copy playable from more services")
    func dedupe() {
        let index = LibraryIndex(items: [
            item("Blinding Lights", "The Weeknd", playlist: "a", spotify: "s1", added: 20),
            item("Blinding Lights", "The Weeknd", playlist: "b", youtube: "y1", spotify: "s1", added: 10),
            item("blinding lights", "The Weeknd, Someone", playlist: "c", added: 30),
        ])
        #expect(index.songs.count == 1)
        #expect(index.songs[0].item.playlistID == "b")
        #expect(index.songs[0].addedAt == Date(timeIntervalSince1970: 10))
    }

    @Test("albums group by name under the lead artist; artists collect their songs and albums")
    func grouping() {
        let index = LibraryIndex(items: [
            item("Starboy", "The Weeknd feat. Daft Punk", album: "Starboy", index: 0),
            item("Reminder", "The Weeknd", album: "Starboy", index: 1),
            item("Blinding Lights", "The Weeknd", album: "After Hours", index: 2),
            item("Yellow", "Coldplay", album: "Parachutes", index: 3),
            item("Loose Track", "Coldplay", index: 4),
            item("No Artist", nil, index: 5),
        ])
        #expect(index.songs.count == 6)
        #expect(index.albums.map(\.title) == ["After Hours", "Parachutes", "Starboy"])
        #expect(index.albums.first { $0.title == "Starboy" }?.songs.count == 2)
        #expect(index.artists.map(\.name) == ["Coldplay", "The Weeknd"])
        let weeknd = index.artists.first { $0.name == "The Weeknd" }
        #expect(weeknd?.songs.count == 3)
        #expect(weeknd?.albums.count == 2)
    }

    @Test("lead artist cuts at the usual credit separators")
    func leadArtist() {
        #expect(LibraryIndex.leadArtist("Calvin Harris, Dua Lipa") == "Calvin Harris")
        #expect(LibraryIndex.leadArtist("Calvin Harris & Dua Lipa") == "Calvin Harris")
        #expect(LibraryIndex.leadArtist("Calvin Harris ft. Dua Lipa") == "Calvin Harris")
        #expect(LibraryIndex.leadArtist("Coldplay") == "Coldplay")
    }
}
