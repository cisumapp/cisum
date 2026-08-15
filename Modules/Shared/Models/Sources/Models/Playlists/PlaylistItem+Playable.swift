//
//  PlaylistItem+Playable.swift
//  Models
//
//  Bridging imported playlist rows onto PlayableRef.
//

import Foundation

public extension PlaylistItem {
    /// The services this item is known to exist on, best-known id first.
    ///
    /// `PlaylistItem` still carries a column per provider — `youtubeID`, `spotifyID`, `tidalID`,
    /// and so on — the same shape `Song` has just moved away from. Playlist import is its own
    /// subsystem and is out of scope for this pass, so the columns stay for now; what changes is
    /// that the **provider-priority ladder lives here rather than being retyped at every call
    /// site**. Three views had their own slightly different version of it.
    ///
    /// When playlist import is reworked, this becomes a `sources` relationship like `Song`'s and
    /// the ladder disappears entirely. Until then this is the single place to change it.
    ///
    /// - Note: A user-installed plugin cannot appear here, for exactly the reason `Song` was
    ///   changed: there is no column for it. Imported playlist rows can only be played from the
    ///   eight services that were hardcoded.
    var knownSources: [(sourceID: String, trackID: String)] {
        let candidates: [(String, String?)] = [
            ("tidal", tidalID),
            ("qobuz", qobuzID),
            ("apple_music", appleMusicID),
            ("youtube_music", youtubeMusicID),
            ("youtube", youtubeID),
            ("spotify", spotifyID),
            ("soundcloud", soundcloudID),
            ("deezer", deezerID),
        ]

        return candidates.compactMap { sourceID, trackID in
            guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return (sourceID, trimmed)
        }
    }

    /// A `PlayableRef` for this item, preferring the user's chosen services.
    ///
    /// Returns `nil` when the item has no provider id at all — an import that never resolved.
    /// Such a row needs matching before it can play, which is the resolver's job, not a view's.
    func playableRef(preferring preferred: [String] = []) -> PlayableRef? {
        let available = knownSources
        guard !available.isEmpty else { return nil }

        let chosen = preferred
            .lazy
            .compactMap { wanted in available.first { $0.sourceID == wanted } }
            .first
            ?? available[0]

        return PlayableRef(
            songID: canonicalSongID,
            sourceID: chosen.sourceID,
            sourceTrackID: chosen.trackID,
            title: title,
            artist: artistName ?? "",
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            durationSeconds: durationSeconds
        )
    }
}
