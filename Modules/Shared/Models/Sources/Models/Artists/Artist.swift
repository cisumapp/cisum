//
//  Artist.swift
//  Models
//
//  Created by Aarav Gupta on 29/04/26.
//

import Foundation
import SwiftData

@Model
public final class Artist {
    @Attribute(.unique) public var artistID: String

    public var displayName: String
    public var normalizedName: String
    public var artworkURLString: String?
    public var genresJSONString: String?

    public var spotifyArtistID: String?
    public var spotifyArtistURI: String?
    public var youtubeChannelID: String?
    public var youtubeMusicBrowseID: String?
    public var appleMusicArtistID: String?

    /// The best photo found for the artist page, kept so the next visit opens on it.
    public var bannerURLString: String?
    /// The artist page last fetched from the catalogue (JSON), so a visit opens instantly.
    public var catalogPageData: Data?
    public var catalogFetchedAt: Date?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Song.artist)
    public var songs: [Song]

    @Relationship(deleteRule: .cascade)
    public var albums: [Album]

    public init(
        artistID: String = UUID().uuidString,
        displayName: String,
        normalizedName: String,
        artworkURLString: String? = nil,
        genresJSONString: String? = nil,
        spotifyArtistID: String? = nil,
        spotifyArtistURI: String? = nil,
        youtubeChannelID: String? = nil,
        youtubeMusicBrowseID: String? = nil,
        appleMusicArtistID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.artistID = artistID
        self.displayName = displayName
        self.normalizedName = normalizedName
        self.artworkURLString = artworkURLString
        self.genresJSONString = genresJSONString
        self.spotifyArtistID = spotifyArtistID
        self.spotifyArtistURI = spotifyArtistURI
        self.youtubeChannelID = youtubeChannelID
        self.youtubeMusicBrowseID = youtubeMusicBrowseID
        self.appleMusicArtistID = appleMusicArtistID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.songs = []
        self.albums = []
    }
}

public extension Artist {
    /// The saved artist for a YouTube Music artist, adding it the first time, so an artist page
    /// opened from search or from another artist's page is the same page.
    @MainActor
    static func findOrInsert(youtubeBrowseID browseID: String, name: String, artworkURL: URL?, in context: ModelContext) -> Artist {
        let descriptor = FetchDescriptor<Artist>(predicate: #Predicate<Artist> { $0.youtubeMusicBrowseID == browseID })
        if let artist = (try? context.fetch(descriptor))?.first {
            return artist
        }
        let artist = Artist(
            displayName: name,
            normalizedName: name.lowercased(),
            artworkURLString: artworkURL?.absoluteString,
            youtubeMusicBrowseID: browseID
        )
        context.insert(artist)
        return artist
    }
}
