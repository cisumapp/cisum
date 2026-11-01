//
//  YouTubeSource.swift
//  Core
//
//  YouTube as a MusicSource, exactly like any downloaded plugin.
//

import Foundation
import Models
import Player
import ProviderSDK
import Utilities
import YouTubeSDK

// `Player` re-exports `PlaybackCore`, which owns the decision about what AVPlayer can play. Format
// compatibility is playback policy rather than this adapter's private opinion, so a second adapter
// cannot answer the same question differently.

/// YouTube Music, adapted to `MusicSource`.
///
/// **The point of this file is that it is unremarkable.** YouTubeSDK is by far the largest and
/// most capable provider in the app — InnerTube, signature deciphering, HLS, PO tokens, OAuth —
/// and yet from the outside it presents the same three methods a forty-line JavaScript plugin
/// does. Nothing above `MusicSource` can tell them apart, which is what stops YouTube from
/// becoming the application's default music-identity engine again simply because it happens to
/// know the most.
///
/// The SDK keeps every bit of its capability. What it loses is the ability to *decide* things on
/// cisum's behalf.
public actor YouTubeMusicSource: MusicSource {
    public nonisolated let id = "youtube_music"
    public nonisolated let displayName = "YouTube Music"
    public nonisolated let capabilities: SourceCapability = [.search, .stream]

    private let youtube: YouTube

    public init(youtube: YouTube) {
        self.youtube = youtube
    }

    /// Songs-shelf search, so matching sees catalogue tracks rather than every upload.
    ///
    /// The plain `search(_:)` falls back to generic YouTube search, which is how a fan upload or a
    /// music-video edit used to get bound to a song. Each result carries its `musicVideoType`, so
    /// the matcher can prefer the official audio and refuse user uploads outright.
    public func searchTracks(query: String, limit: Int) async throws -> [SourceTrack] {
        let songs = try await youtube.music.searchSongs(query)

        return songs.prefix(limit).map { song in
            SourceTrack(
                id: song.videoId,
                title: song.title,
                artist: song.artists.joined(separator: ", "),
                album: song.album,
                durationSeconds: song.duration,
                artworkURL: song.thumbnailURL,
                isExplicit: song.isExplicit,
                recordingKind: Self.recordingKind(song.videoType)
            )
        }
    }

    static func recordingKind(_ type: YouTubeMusicSong.VideoType?) -> RecordingKind? {
        switch type {
        case .officialAudio: .officialAudio
        case .musicVideo: .musicVideo
        case .userUpload: .userUpload
        case .other, nil: nil
        }
    }

    /// Every way this track can be played, in the adapter's own order.
    ///
    /// Uses `YouTubeStreamResolver`, not `YouTubeClient.video(id:)`.
    ///
    /// That distinction is the whole reason playback broke. `video(id:)` sits under the header
    /// "SmartTubeIOS-style — no decipher" and documents that it "does NOT do exhaustive retry —
    /// the ViewModel handles that". It is a single unauthenticated iOS request: no signature
    /// deciphering, no n-parameter descrambling, no PO token, no client fallback. Without
    /// `html5Preference` and a signature timestamp, YouTube answers with `serverAbrStreamingUrl`
    /// — SABR, which AVPlayer cannot play — and no HLS manifest, so every accessor returns nil.
    ///
    /// `YouTubeStreamResolver.resolve` is the ladder that actually works: unauthenticated Android
    /// first for time-to-first-byte, then a seven-stage InnerTube client chain, then WKWebView HLS
    /// extraction, deciphering and descrambling every URL along the way.
    ///
    /// **This list is no longer what decides playback.** Every parsed format that this platform can
    /// play becomes a candidate and `CandidateRankingPolicy` orders them; the position in this array
    /// survives only as a tie-break between candidates that are equal on every other dimension. The
    /// compatibility judgement — which parsed formats may be candidates at all, and why — is
    /// `YouTubeFormatSelection`'s, which makes it through `PlaybackFormatCompatibility` so the rule is
    /// stated once, in the package that owns playback.
    public func streamCandidates(trackID: String, quality _: QualityHint) async throws -> [SourceStream] {
        let info = try await YouTubeStreamResolver.shared.resolve(videoId: trackID, preferAudio: true)

        // The decision — which parsed formats are usable here, in what order, with which headers —
        // lives in `YouTubeFormatSelection` so it can be read and tested as one unit. This method owns
        // only the part that needs the network.
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: info.hlsURL,
            formats: info.formats,
            expiry: Self.expiry(from: info)
        )

        guard !candidates.isEmpty else {
            throw SourceError.noStreamAvailable(source: id, trackID: trackID)
        }
        return candidates
    }

    public func stream(trackID: String, quality: QualityHint) async throws -> SourceStream {
        guard let best = try await streamCandidates(trackID: trackID, quality: quality).first else {
            throw SourceError.noStreamAvailable(source: id, trackID: trackID)
        }
        return best
    }

    /// When YouTube's URLs stop working.
    ///
    /// `googlevideo` URLs are signed with an expiry, typically around six hours. The SDK reports
    /// it as `expiresInSeconds`; when it is missing, returning `nil` lets the store apply its own
    /// conservative default rather than this file inventing one.
    /// YouTube's expiry, when it can be known.
    ///
    /// `PlayerInfo` does not surface one, so this is always nil and the store applies its own
    /// conservative default instead. That is the documented meaning of a nil expiry — "unknown",
    /// not "never" — and erring short costs one cheap re-resolve, where erring long costs a
    /// playback failure the user sees.
    private static func expiry(from _: PlayerInfo) -> Date? {
        nil
    }
}

/// Plain YouTube — videos rather than catalogue tracks.
///
/// Separate from `YouTubeMusicSource` because the two index different catalogues and share no id
/// space: a video id valid in one is not reliably valid in the other. Collapsing them would
/// reintroduce exactly the identifier conflation the reset exists to remove.
public actor YouTubeVideoSource: MusicSource {
    public nonisolated let id = "youtube"
    public nonisolated let displayName = "YouTube"
    public nonisolated let capabilities: SourceCapability = [.search, .stream]

    private let youtube: YouTube
    private let music: YouTubeMusicSource

    public init(youtube: YouTube) {
        self.youtube = youtube
        self.music = YouTubeMusicSource(youtube: youtube)
    }

    public func searchTracks(query: String, limit: Int) async throws -> [SourceTrack] {
        let results = try await youtube.main.search(query)

        return results.items.compactMap { item -> SourceTrack? in
            guard case let .video(video) = item else { return nil }
            let topic = Self.topicArtist(video.author)
            return SourceTrack(
                id: video.id,
                title: video.title,
                artist: topic ?? Self.channelArtist(video.author),
                durationSeconds: TimeInterval(video.lengthInSeconds),
                artworkURL: video.thumbnailURL.flatMap(URL.init(string:)),
                // ponytail: "Artist - Topic" channels are YouTube's auto-generated label uploads,
                // the same audio YouTube Music serves. Everything else is a video of some kind; a
                // search result cannot tell an official video from a fan upload, so it is only ever
                // treated as a video and never as the official audio.
                recordingKind: topic == nil ? .musicVideo : .officialAudio
            )
        }
        .prefix(limit)
        .map(\.self)
    }

    /// The artist behind an auto-generated `"<Artist> - Topic"` channel, or nil for any other channel.
    static func topicArtist(_ author: String) -> String? {
        let suffix = " - Topic"
        guard author.hasSuffix(suffix) else { return nil }
        let artist = author.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
        return artist.isEmpty ? nil : artist
    }

    /// A channel name as the artist it stands for: `"TheWeekndVEVO"` → `"TheWeeknd"`.
    ///
    /// The matcher only accepts a video whose channel *is* the artist, so a label's VEVO channel
    /// has to read as the artist's name to count as official.
    static func channelArtist(_ author: String) -> String {
        guard author.hasSuffix("VEVO"), author.count > 4 else { return author }
        return String(author.dropLast(4))
    }

    /// Resolution is identical for both catalogues — same player endpoint, same formats — so it
    /// delegates rather than duplicating the format selection.
    public func stream(trackID: String, quality: QualityHint) async throws -> SourceStream {
        try await music.stream(trackID: trackID, quality: quality)
    }

    public func streamCandidates(trackID: String, quality: QualityHint) async throws -> [SourceStream] {
        try await music.streamCandidates(trackID: trackID, quality: quality)
    }
}
