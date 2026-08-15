//
//  YouTubeSource.swift
//  Core
//
//  YouTube as a MusicSource, exactly like any downloaded plugin.
//

import Foundation
import Models
import ProviderSDK
import Utilities
import YouTubeSDK

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

    public func searchTracks(query: String, limit: Int) async throws -> [SourceTrack] {
        let songs = try await youtube.music.search(query)

        return songs.prefix(limit).map { song in
            SourceTrack(
                id: song.videoId,
                title: song.title,
                artist: song.artists.joined(separator: ", "),
                album: song.album,
                durationSeconds: song.duration,
                artworkURL: song.thumbnailURL,
                isExplicit: song.isExplicit
            )
        }
    }

    /// Every way this track can be played, best first.
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
    public func streamCandidates(trackID: String, quality _: QualityHint) async throws -> [SourceStream] {
        let info = try await YouTubeStreamResolver.shared.resolve(videoId: trackID, preferAudio: true)
        let expiry = Self.expiry(from: info)

        var candidates: [SourceStream] = []

        // Each candidate carries the User-Agent of the client its URL was signed for. The CDN
        // checks it, and a mismatch is rejected with no error thrown anywhere — it surfaces only
        // as `CRABS ... ReadError` in the system log while the player sits at 0:00.
        if let hls = info.hlsURL {
            candidates.append(SourceStream(
                url: hls,
                kind: .hls,
                mimeType: "application/x-mpegURL",
                qualityLabel: "Adaptive",
                expiresAt: expiry,
                headers: ["User-Agent": InnerTubeClients.WebSafari.userAgent],
                requiresProxyLoader: hls.absoluteString.contains("manifest.googlevideo.com")
            ))
        }

        if let audio = info.bestAdaptiveAudioURL {
            candidates.append(SourceStream(
                url: audio,
                kind: .direct,
                mimeType: "audio/mp4",
                expiresAt: expiry,
                headers: ["User-Agent": InnerTubeClients.WebSafari.userAgent]
            ))
        }

        // Muxed last on quality, but it is the candidate with no strings attached: an
        // Android-signed progressive URL that needs only the Android UA — no manifest, no
        // per-segment token, no resource-loader delegate.
        if let muxed = info.bestMuxedDownloadURL {
            candidates.append(SourceStream(
                url: muxed,
                kind: .direct,
                mimeType: "video/mp4",
                expiresAt: expiry,
                headers: ["User-Agent": InnerTubeClients.Android.userAgent]
            ))
        }

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
            return SourceTrack(
                id: video.id,
                title: video.title,
                artist: video.author,
                durationSeconds: TimeInterval(video.lengthInSeconds),
                artworkURL: video.thumbnailURL.flatMap(URL.init(string:))
            )
        }
        .prefix(limit)
        .map(\.self)
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
