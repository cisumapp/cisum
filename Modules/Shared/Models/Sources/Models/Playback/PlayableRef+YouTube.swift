//
//  PlayableRef+YouTube.swift
//  Models
//
//  Building a ref from YouTube data without Models depending on YouTubeSDK.
//

import Foundation

public extension PlayableRef {
    /// A ref for a YouTube Music song.
    ///
    /// Takes scalars rather than a `YouTubeMusicSong` because `Models` must not depend on
    /// `YouTubeSDK` — that edge is what let a single provider's types spread through the whole
    /// app last time. Callers already hold the SDK type and pass its fields across.
    ///
    /// `songID` is `nil`: this is an ad-hoc play of a search or chart result, with nothing yet
    /// persisted. It plays, but a second play resolves again; saving the track to the library is
    /// what makes it cheap.
    static func youtubeMusic(
        videoID: String,
        title: String,
        artist: String,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil
    ) -> PlayableRef {
        PlayableRef(
            songID: nil,
            sourceID: "youtube_music",
            sourceTrackID: videoID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            durationSeconds: durationSeconds
        )
    }

    /// A ref for a plain YouTube video.
    ///
    /// Distinct from `youtubeMusic` because the two index different catalogues and do not share an
    /// id space — a video id valid in one is not reliably valid in the other.
    static func youtubeVideo(
        videoID: String,
        title: String,
        artist: String,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil
    ) -> PlayableRef {
        PlayableRef(
            songID: nil,
            sourceID: "youtube",
            sourceTrackID: videoID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            durationSeconds: durationSeconds
        )
    }
}
