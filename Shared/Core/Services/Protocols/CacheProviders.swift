import Foundation
import SwiftUI
import YouTubeSDK

protocol VideoMetadataCaching: Actor {
    func resolve(
        id: String,
        metricsEnabled: Bool,
        fetcher: @Sendable @escaping (String) async throws -> YouTubeVideo
    ) async throws -> VideoMetadataCache.Entry

    func prefetch(
        ids: [String],
        maxConcurrent: Int,
        mode: PrefetchModeOverride,
        metricsEnabled: Bool,
        fetcher: @Sendable @escaping (String) async throws -> YouTubeVideo
    ) async

    func remove(_ id: String)
}

@MainActor
protocol SearchResultsCaching: AnyObject {
    func getMusicResults(for query: String) -> SearchResultsCache.Lookup<YouTubeMusicSong>?
    func setMusicResults(_ results: [YouTubeMusicSong], for query: String)
    func getVideoResults(for query: String) -> SearchResultsCache.Lookup<YouTubeSearchResult>?
    func setVideoResults(_ results: [YouTubeSearchResult], for query: String)
    func clear()
}

protocol PlaybackMetricsRecording: Actor {
    func recordTapToPlay(durationMs: Double)
}

@MainActor
protocol StreamingProviderSettingsReading: AnyObject {
    var tidalPreferredQualityRawValue: String { get }
}

#if os(iOS)
protocol ArtworkColorExtracting: Actor {
    func dominantColor(from imageData: Data, cacheKey: String?) -> Color
}
#endif

extension VideoMetadataCache: VideoMetadataCaching {}
extension SearchResultsCache: SearchResultsCaching {}
extension PlaybackMetricsStore: PlaybackMetricsRecording {}
extension StreamingProviderSettings: StreamingProviderSettingsReading {}
#if os(iOS)
extension ArtworkDominantColorExtractor: ArtworkColorExtracting {}
#endif