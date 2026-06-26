//
//  Song.swift
//  Models
//
//  Created by Aarav Gupta on 29/04/26.
//

import Foundation
import SwiftData

@Model
public final class Song {
    @Attribute(.unique) public var songID: String

    public var title: String
    public var normalizedTitle: String
    public var primaryArtistName: String?
    public var primaryArtistID: String?
    public var albumTitle: String?
    public var albumID: String?
    public var durationSeconds: Double?
    public var artworkURLString: String?
    public var isExplicit: Bool

    public var providerFingerprint: String

    /// Canonical ISRC. Nil when no provider supplied one (YouTube videos, untagged local files).
    /// NOT a unique attribute — ISRCs collide across masters/compilations; uniqueness is enforced
    /// logically by the reconciler, not the store. `songID` remains the unique key.
    public var isrc: String?

    /// Raw value of the provider whose metadata is the authoritative base for this canonical Song.
    public var metadataBaseProviderRawValue: String?

    public var spotifyTrackID: String?
    public var spotifyTrackURI: String?
    public var spotifyPreviewURLString: String?

    public var youtubeVideoID: String?
    public var youtubeMusicVideoID: String?
    public var tidalID: String?
    public var qobuzID: String?
    public var soundcloudID: String?
    public var deezerID: String?

    public var appleMusicSongID: String?

    public var preferredFallbackProviderRawValue: String?
    public var cachedFallbackMediaID: String?
    public var lastResolvedAt: Date?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify)
    public var artist: Artist?

    @Relationship(deleteRule: .nullify)
    public var album: Album?

    public init(
        songID: String = UUID().uuidString,
        title: String,
        normalizedTitle: String,
        primaryArtistName: String? = nil,
        primaryArtistID: String? = nil,
        albumTitle: String? = nil,
        albumID: String? = nil,
        durationSeconds: Double? = nil,
        artworkURLString: String? = nil,
        isExplicit: Bool = false,
        providerFingerprint: String,
        isrc: String? = nil,
        metadataBaseProviderRawValue: String? = nil,
        spotifyTrackID: String? = nil,
        spotifyTrackURI: String? = nil,
        spotifyPreviewURLString: String? = nil,
        youtubeVideoID: String? = nil,
        youtubeMusicVideoID: String? = nil,
        tidalID: String? = nil,
        qobuzID: String? = nil,
        soundcloudID: String? = nil,
        deezerID: String? = nil,
        appleMusicSongID: String? = nil,
        preferredFallbackProviderRawValue: String? = nil,
        cachedFallbackMediaID: String? = nil,
        lastResolvedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.songID = songID
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.primaryArtistName = primaryArtistName
        self.primaryArtistID = primaryArtistID
        self.albumTitle = albumTitle
        self.albumID = albumID
        self.durationSeconds = durationSeconds
        self.artworkURLString = artworkURLString
        self.isExplicit = isExplicit
        self.providerFingerprint = providerFingerprint
        self.isrc = isrc
        self.metadataBaseProviderRawValue = metadataBaseProviderRawValue
        self.spotifyTrackID = spotifyTrackID
        self.spotifyTrackURI = spotifyTrackURI
        self.spotifyPreviewURLString = spotifyPreviewURLString
        self.youtubeVideoID = youtubeVideoID
        self.youtubeMusicVideoID = youtubeMusicVideoID
        self.tidalID = tidalID
        self.qobuzID = qobuzID
        self.soundcloudID = soundcloudID
        self.deezerID = deezerID
        self.appleMusicSongID = appleMusicSongID
        self.preferredFallbackProviderRawValue = preferredFallbackProviderRawValue
        self.cachedFallbackMediaID = cachedFallbackMediaID
        self.lastResolvedAt = lastResolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var preferredFallbackProvider: MediaProvider? {
        get {
            guard let rawValue = preferredFallbackProviderRawValue else { return nil }
            return MediaProvider(rawValue: rawValue)
        }
        set {
            preferredFallbackProviderRawValue = newValue?.rawValue
        }
    }

    /// Provider whose metadata is the authoritative base for this canonical Song.
    public var metadataBaseProvider: MediaProvider? {
        get {
            guard let rawValue = metadataBaseProviderRawValue else { return nil }
            return MediaProvider(rawValue: rawValue)
        }
        set {
            metadataBaseProviderRawValue = newValue?.rawValue
        }
    }
}
