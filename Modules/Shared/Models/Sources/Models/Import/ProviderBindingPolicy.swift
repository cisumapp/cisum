//
//  ProviderBindingPolicy.swift
//  Models
//
//  How a resolved provider representation is persisted (decision U-4).
//
//  Kept as a pure decision so the reuse rules — in particular "reuse rather than duplicate" and
//  "never fabricate a canonical Song" — are verifiable without a SwiftData store.
//

import Foundation

/// Decides how a resolved provider representation should be written.
public enum ProviderBindingPolicy {
    /// The write a caller should perform.
    public enum Action: Equatable, Sendable {
        /// A row already exists for `(sourceID, sourceTrackID)` — update it in place.
        case updateExisting

        /// No row exists, but canonical identity is known — create the representation on that song.
        case bindToSong(songID: String)

        /// No row exists and no canonical identity is known — create a standalone (ad-hoc) binding.
        case createOrphan
    }

    /// Chooses the action for a resolved representation.
    ///
    /// - Parameters:
    ///   - existingBindingFound: Whether a row already exists for this `(sourceID, sourceTrackID)`.
    ///   - resolvedSongID: The canonical song id the ref resolved to, when one exists. This is the
    ///     **only** way canonical identity is attached; an absent id never fabricates a song.
    ///
    /// Ordering matters: an existing row is reused even when a canonical song is now known, so a
    /// representation can be promoted from orphan to bound without a second row being created.
    public static func action(existingBindingFound: Bool, resolvedSongID: String?) -> Action {
        if existingBindingFound {
            return .updateExisting
        }
        if let resolvedSongID, !resolvedSongID.isEmpty {
            return .bindToSong(songID: resolvedSongID)
        }
        return .createOrphan
    }

    /// Whether a stored YouTube binding was chosen by search on the song's behalf.
    ///
    /// A song whose identity came from another service (a Spotify import, a catalogue plugin) only
    /// has a YouTube row because the resolver searched for it — and before official-audio matching
    /// that search could bind a music-video edit or a fan upload. Such a row is safe to forget: the
    /// next play re-matches. A song known *only* through YouTube got its row from the user's own
    /// tap or playlist, so it is never a guess and is never dropped.
    public static func isSearchMatchedYouTubeBinding(sourceID: String, siblingSourceIDs: [String]) -> Bool {
        let youtube: Set = ["youtube_music", "youtube"]
        return youtube.contains(sourceID) && siblingSourceIDs.contains { !youtube.contains($0) }
    }
}
