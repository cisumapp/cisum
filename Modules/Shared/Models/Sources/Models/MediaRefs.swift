//
//  MediaRefs.swift
//  cisum
//
//  Neutral, provider-agnostic references carried by FederatedSearchPayload so that
//  Models depends on no provider SDK. Provider-aware modules (Search, Player, Playlists)
//  map their SDK types ↔ these refs at the boundary.
//

import Foundation

/// A neutral YouTube media reference (music song or video). Carries only the scalars
/// the player/search/ranking paths need — enough to drive playback, radio seeding, and
/// artist-signal ranking without embedding a `YouTubeSDK` type.
public struct YouTubeMediaRef: Sendable, Hashable {
    public let videoID: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let durationSeconds: Double?
    public let isExplicit: Bool
    /// `true` for a YouTube Music song, `false` for a plain YouTube video.
    public let isMusic: Bool
    /// Raw view-count string (e.g. "1.2M views"), used for artist-signal ranking. Videos only.
    public let viewCount: String?

    public init(
        videoID: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil,
        isExplicit: Bool = false,
        isMusic: Bool,
        viewCount: String? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
        self.isExplicit = isExplicit
        self.isMusic = isMusic
        self.viewCount = viewCount
    }
}

/// A neutral provider representation (one provider's view of a track). Mirrors the scalar
/// subset of `ProviderSDK.TrackRepresentation` that the resolver actually consumes.
public struct MediaRepresentation: Sendable, Hashable, Codable {
    public let providerID: String
    public let providerTrackID: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Double?
    public let isrc: String?
    public let artworkURL: URL?

    public init(
        providerID: String,
        providerTrackID: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double? = nil,
        isrc: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.providerID = providerID
        self.providerTrackID = providerTrackID
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isrc = isrc
        self.artworkURL = artworkURL
    }
}

/// A neutral reference to a ProviderSDK-resolved track (SoundCloud, Tidal, Qobuz, Deezer, …).
/// Carries the canonical id + scalar metadata + representations so the Search resolver can
/// reconstruct what it needs without Models naming a `ProviderSDK` type.
public struct ProviderMediaRef: Sendable, Hashable {
    public let canonicalID: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let durationSeconds: Double?
    public let representations: [MediaRepresentation]

    public init(
        canonicalID: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil,
        representations: [MediaRepresentation]
    ) {
        self.canonicalID = canonicalID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
        self.representations = representations
    }
}
