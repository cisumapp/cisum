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

    // MARK: Provenance

    //
    // cisum picks the best source per FIELD, not one authoritative provider per song. Spotify may
    // win on ISRC and title while artwork comes from elsewhere and playback from somewhere else
    // again. These record which source each accepted value came from, so a later, better answer
    // can replace it deliberately rather than by whoever wrote last.

    /// Source whose title and artist were accepted.
    public var titleSourceID: String?
    /// Source whose artwork was accepted.
    public var artworkSourceID: String?
    /// Source that supplied the ISRC.
    public var isrcSourceID: String?

    /// Every service's representation of this song.
    ///
    /// Replaces the previous hardcoded column-per-provider layout (`spotifyTrackID`,
    /// `youtubeVideoID`, `tidalID`, `qobuzID`, `soundcloudID`, `deezerID`, `appleMusicSongID`,
    /// `preferredFallbackProviderRawValue`, `cachedFallbackMediaID`). That shape could not
    /// represent a user-installed plugin at all: a plugin cannot be given a column, and the closed
    /// `MediaProvider` enum could not be given a case. `SongSource.sourceID` is an open string,
    /// so any plugin is a first-class identity source with no schema change.
    @Relationship(deleteRule: .cascade)
    public var sources: [SongSource]

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
        titleSourceID: String? = nil,
        artworkSourceID: String? = nil,
        isrcSourceID: String? = nil,
        sources: [SongSource] = [],
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
        self.titleSourceID = titleSourceID
        self.artworkSourceID = artworkSourceID
        self.isrcSourceID = isrcSourceID
        self.sources = sources
        self.lastResolvedAt = lastResolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Source lookup

    /// This song's representation on a given service, if one is known.
    public func source(_ sourceID: String) -> SongSource? {
        sources.first { $0.sourceID == sourceID }
    }

    /// Records or updates how a service represents this song.
    ///
    /// Idempotent: matching an already-known (song, source) pair updates the existing row rather
    /// than accumulating duplicates.
    @discardableResult
    public func bind(
        sourceID: String,
        sourceTrackID: String,
        isrc: String? = nil,
        durationSeconds: Double? = nil,
        audioQualityLabel: String? = nil,
        allowsStreamCaching: Bool = true
    ) -> SongSource {
        if let existing = source(sourceID) {
            // A changed track id invalidates the cached URL — it points at the old track.
            if existing.sourceTrackID != sourceTrackID {
                existing.sourceTrackID = sourceTrackID
                existing.invalidateStream()
            }
            existing.isrc = isrc ?? existing.isrc
            existing.durationSeconds = durationSeconds ?? existing.durationSeconds
            existing.audioQualityLabel = audioQualityLabel ?? existing.audioQualityLabel
            existing.allowsStreamCaching = allowsStreamCaching
            existing.lastVerifiedAt = .now
            updatedAt = .now
            return existing
        }

        let source = SongSource(
            sourceID: sourceID,
            sourceTrackID: sourceTrackID,
            isrc: isrc,
            durationSeconds: durationSeconds,
            audioQualityLabel: audioQualityLabel,
            allowsStreamCaching: allowsStreamCaching,
            lastVerifiedAt: .now
        )
        source.song = self
        sources.append(source)
        updatedAt = .now
        return source
    }

    /// A `PlayableRef` for this song on a given service, if it has a representation there.
    public func playableRef(on sourceID: String) -> PlayableRef? {
        source(sourceID).map(ref(from:))
    }

    /// A `PlayableRef` using the best available service.
    ///
    /// - Parameter preferring: Source ids in preference order, best first — usually the user's
    ///   plugin ordering, from `\.preferredSourceIDs`.
    /// - Returns: `nil` only when the song has no representation on any service at all, which
    ///   means it has never been matched and cannot be played without searching first.
    ///
    /// This is what replaced the old per-provider column ladder at call sites — the
    /// `if spotify … else if youtube … else return nil` block that had to be repeated, slightly
    /// differently, everywhere a list of songs could be played.
    public func playableRef(preferring preferred: [String] = []) -> PlayableRef? {
        for sourceID in preferred {
            if let match = source(sourceID) {
                return ref(from: match)
            }
        }
        return sources.first.map(ref(from:))
    }

    private func ref(from source: SongSource) -> PlayableRef {
        PlayableRef(
            songID: songID,
            sourceID: source.sourceID,
            sourceTrackID: source.sourceTrackID,
            title: title,
            artist: primaryArtistName ?? "",
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            durationSeconds: durationSeconds
        )
    }
}
