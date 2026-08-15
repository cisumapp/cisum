//
//  FederatedSearchItem+Playable.swift
//  Models
//
//  Turning a search result into something the player can take.
//

import Foundation

public extension FederatedSearchItem {
    /// A `PlayableRef` for this search result, if it is playable.
    ///
    /// **This is the change that removes "search, then resolve, then hand the player a closure".**
    /// Previously each playback path in `SearchView` resolved the stream itself, wrapped the
    /// result in an `ExternalQueueTrack` carrying a `resolvePayload` thunk, and handed that over —
    /// so resolution happened before playback even started, on the main actor, with no identity
    /// left behind to cache against.
    ///
    /// Now the view produces an identity and stops. The player resolves it, and persists the
    /// binding so the next play is a lookup.
    ///
    /// Returns `nil` for artists and playlists, which are navigation targets rather than tracks.
    var playableRef: PlayableRef? {
        switch payload {
        case let .youtube(ref):
            PlayableRef(youtube: ref)

        case let .spotify(track):
            PlayableRef(
                songID: nil,
                sourceID: "spotify",
                sourceTrackID: track.id,
                title: track.title,
                artist: track.artistName,
                artworkURL: track.artworkURL,
                durationSeconds: track.durationSeconds
            )

        case let .providerSDK(ref):
            // The first representation is the source that actually returned this result.
            // `sourceTrackID` is only meaningful paired with its `providerID`, so both are taken
            // from the same representation rather than mixed.
            ref.representations.first.map { representation in
                PlayableRef(
                    songID: nil,
                    sourceID: representation.providerID,
                    sourceTrackID: representation.providerTrackID,
                    title: ref.title,
                    artist: ref.artist,
                    artworkURL: ref.artworkURL,
                    durationSeconds: ref.durationSeconds
                )
            }

        case .spotifyArtist, .spotifyPlaylist:
            nil
        }
    }
}
