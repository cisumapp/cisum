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

    public func stream(trackID: String, quality _: QualityHint) async throws -> SourceStream {
        let video = try await youtube.main.video(id: trackID)

        // Audio-only first: this is a music player, and a muxed stream downloads video frames
        // nobody looks at. HLS is the fallback because it always plays, at the cost of adaptive
        // switching and slower start.
        if let audio = video.bestAudioStream, let urlString = audio.playbackUrl,
           let url = URL(string: urlString)
        {
            return SourceStream(
                url: url,
                kind: .direct,
                mimeType: audio.mimeType,
                bitrate: audio.bitrate,
                qualityLabel: audio.audioQuality,
                expiresAt: Self.expiry(from: video),
                isCacheable: true
            )
        }

        if let hls = video.hlsURL {
            return SourceStream(
                url: hls,
                kind: .hls,
                mimeType: "application/vnd.apple.mpegurl",
                qualityLabel: "Adaptive",
                expiresAt: Self.expiry(from: video),
                isCacheable: true
            )
        }

        throw SourceError.noStreamAvailable(source: id, trackID: trackID)
    }

    /// When YouTube's URLs stop working.
    ///
    /// `googlevideo` URLs are signed with an expiry, typically around six hours. The SDK reports
    /// it as `expiresInSeconds`; when it is missing, returning `nil` lets the store apply its own
    /// conservative default rather than this file inventing one.
    private static func expiry(from video: YouTubeVideo) -> Date? {
        guard let seconds = video.streamingData?.expiresInSeconds,
              let interval = TimeInterval(seconds)
        else { return nil }
        return Date.now.addingTimeInterval(interval)
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

    /// Stream resolution is identical for both catalogues — same player endpoint, same formats —
    /// so it delegates rather than duplicating the format-selection logic.
    public func stream(trackID: String, quality: QualityHint) async throws -> SourceStream {
        try await music.stream(trackID: trackID, quality: quality)
    }
}
