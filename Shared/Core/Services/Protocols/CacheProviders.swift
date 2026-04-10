import Foundation
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

extension VideoMetadataCache: VideoMetadataCaching {}
extension SearchResultsCache: SearchResultsCaching {}