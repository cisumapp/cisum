//
//  IncomingTrack.swift
//  Models
//
//  Provider-neutral track produced by every ImportService and consumed by the
//  canonical-song reconciler. No SDK import — keeps Models a dependency leaf.
//

import Foundation

/// Provider-neutral track produced by every ImportService and consumed by the reconciler.
public struct IncomingTrack: Sendable, Hashable {
    public let provider: MediaProvider
    public let providerTrackID: String
    public let title: String
    public let artistName: String?
    public let albumName: String?
    public let isrc: String?
    public let durationSeconds: Double?
    public let artworkURLString: String?
    public let isExplicit: Bool
    public let spotifyTrackURI: String?
    public let spotifyPreviewURLString: String?

    /// Structured version evidence, when the importing adapter can supply it.
    ///
    /// **No adapter supplies this yet** — none of the seven sources reports a structured version,
    /// so it is `nil` in production and reconciliation falls back to title inference. It is here so
    /// the first adapter that can report one has somewhere to put it, without fabricating evidence
    /// for the sources that cannot.
    public let version: VersionEvidence?

    public init(
        provider: MediaProvider,
        providerTrackID: String,
        title: String,
        artistName: String? = nil,
        albumName: String? = nil,
        isrc: String? = nil,
        durationSeconds: Double? = nil,
        artworkURLString: String? = nil,
        isExplicit: Bool = false,
        spotifyTrackURI: String? = nil,
        spotifyPreviewURLString: String? = nil,
        version: VersionEvidence? = nil
    ) {
        self.provider = provider
        self.providerTrackID = providerTrackID
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.isrc = isrc
        self.durationSeconds = durationSeconds
        self.artworkURLString = artworkURLString
        self.isExplicit = isExplicit
        self.spotifyTrackURI = spotifyTrackURI
        self.spotifyPreviewURLString = spotifyPreviewURLString
        self.version = version
    }
}
