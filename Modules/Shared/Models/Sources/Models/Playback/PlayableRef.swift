//
//  PlayableRef.swift
//  Models
//
//  What the player is handed. An identity, not a closure.
//

import Foundation

/// A track that has already been identified, ready to play.
///
/// This replaces `ExternalQueueTrack`, whose defining field was
/// `resolvePayload: @Sendable @MainActor () async throws -> ExternalStreamPayload` — a **thunk**
/// rather than a thing. A queue entry that carries its own resolver has no identity: nothing to
/// key a cache on, nothing to persist, nothing to compare. That is the mechanical reason the old
/// player had to search and guess on every play, and why "use the stored IDs instead of searching
/// again" was impossible to implement.
///
/// Here, identity is the whole point. Given a `PlayableRef`, obtaining audio is a lookup:
///
/// 1. `SongSource` has a fresh cached URL → play it. **No network.**
/// 2. Cached URL stale → resolve by `sourceTrackID`. **No search.**
/// 3. No `SongSource` for this source → match once, persist, then step 2.
///
/// Matching therefore happens **once per (song, source) pair, ever** — not once per play.
public struct PlayableRef: Sendable, Hashable, Codable {
    /// cisum's canonical song id.
    ///
    /// `nil` for an ad-hoc play of something not yet in the library — a search result played
    /// directly, say. Without it there is nothing to persist a binding against, so such a play
    /// resolves fresh every time; promoting the track to the library is what makes it cheap.
    public let songID: String?

    /// Which service to play from. An open string, matching `SongSource.sourceID`.
    public let sourceID: String

    /// That service's track id. Opaque, and only meaningful with `sourceID`.
    public let sourceTrackID: String

    // MARK: Display

    //
    // Carried so the player can render immediately, before any network work. These are a snapshot
    // for painting the UI, never the source of truth — the canonical Song owns that.

    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let durationSeconds: Double?

    public init(
        songID: String?,
        sourceID: String,
        sourceTrackID: String,
        title: String,
        artist: String,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil
    ) {
        self.songID = songID
        self.sourceID = sourceID
        self.sourceTrackID = sourceTrackID
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
    }

    /// A ref for a YouTube result the user tapped directly.
    ///
    /// `songID` is `nil` because nothing has been matched or saved yet — this is an ad-hoc play of
    /// a search result. It plays fine, but nothing is persisted, so a second play resolves again.
    /// Adding the track to the library is what makes it cheap; see `PlayableRef`'s doc comment.
    ///
    /// - Note: `sourceID` distinguishes YouTube Music from plain YouTube, because the two index
    ///   different catalogues and a video id from one is not reliably valid in the other.
    public init(youtube ref: YouTubeMediaRef) {
        self.init(
            songID: nil,
            sourceID: ref.isMusic ? "youtube_music" : "youtube",
            sourceTrackID: ref.videoID,
            title: ref.title,
            artist: ref.artist,
            artworkURL: ref.artworkURL,
            durationSeconds: ref.durationSeconds
        )
    }

    /// Identity is the (source, track) pair.
    ///
    /// Not the display fields, which can differ between services for the same recording, and not
    /// `songID`, which is absent for ad-hoc plays.
    public static func == (lhs: PlayableRef, rhs: PlayableRef) -> Bool {
        lhs.sourceID == rhs.sourceID && lhs.sourceTrackID == rhs.sourceTrackID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sourceID)
        hasher.combine(sourceTrackID)
    }
}
