//
//  CacheProviders.swift
//  Search
//
//  Moved here from Player during the architecture reset.
//
//  These protocols are typed on YouTubeSDK's YouTubeVideo and YouTubeMusicSong, which leaked
//  a single provider's types through what looked like a generic caching interface. They live
//  in Search now because Search is their only consumer, and Player no longer depends on
//  YouTubeSDK at all. Re-typing them on SourceTrack would make them provider-neutral and is
//  the obvious next step, but it is Search's rewrite, not this one.
//

import Aesthetics
import Caching
import Foundation
import SwiftUI
import YouTubeSDK

public protocol VideoMetadataCaching: Actor {
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
public protocol SearchResultsCaching: AnyObject {
    func getMusicResults(for query: String) -> SearchResultsCache.Lookup<YouTubeMusicSong>?
    func setMusicResults(_ results: [YouTubeMusicSong], for query: String)
    func getVideoResults(for query: String) -> SearchResultsCache.Lookup<YouTubeSearchResult>?
    func setVideoResults(_ results: [YouTubeSearchResult], for query: String)
    func clear()
}

extension VideoMetadataCache: VideoMetadataCaching {}
extension SearchResultsCache: SearchResultsCaching {}
