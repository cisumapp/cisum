//
//  PlaybackMetricsAccumulator.swift
//  PlaybackCore
//
//  Metric storage with the domains kept strictly apart.
//
//  Before this, one store held search-metadata-cache hits and the tap-to-play timing together, so a
//  search cache hit and a playback resolution were counted in the same place and could not be told
//  apart. The domains are separated here — and this type is pure, so the separation is testable.
//

import Foundation

/// The single discoverable definition of every playback/search metric and its semantics.
///
/// Four independent domains, plus one continuity counter:
///
/// 1. **Search metadata cache** — `VideoMetadataCache` resolving YouTube metadata for the *search*
///    path. Never a playback metric.
/// 2. **Playback stream resolution** — how long `PlaybackResolver` took, and whether it was warm or
///    cold (`PlaybackResolutionPath`).
/// 3. **Playback startup proxy** — intent → first time advancement. A proxy, not audible audio.
/// 4. **Playback failures / fallbacks** — fallbacks and stalls.
///
/// 5. **Continuity** — intent → `engine.play()` return, kept only so the old number has a truthful
///    name and honest boundary. It is **not** startup and **not** first audio.
public struct PlaybackMetricsAccumulator: Sendable {
    /// A point-in-time view of every domain, for diagnostics.
    public struct Snapshot: Sendable, Equatable {
        // Search metadata cache domain
        public let searchCacheHitRate: Double
        public let searchCacheHits: Int
        public let searchCacheMisses: Int
        public let avgSearchMetadataResolveMs: Double
        public let searchResolveSampleCount: Int

        // Playback stream-resolution domain
        public let avgPlaybackResolveMs: Double
        public let playbackResolveSampleCount: Int
        public let warmPlaybackResolveCount: Int
        public let coldPlaybackResolveCount: Int

        // Playback startup proxy domain
        public let avgStartupProxyMs: Double
        public let startupCompletedCount: Int
        public let startupFailedCount: Int
        public let startupCancelledCount: Int

        /// Playback failures / fallbacks
        public let fallbackCount: Int
        /// Reserved: no producer records a stall yet (documented, not silently dropped).
        public let stallCount: Int

        // Continuity: intent → engine.play() return (NOT startup, NOT first audio)
        public let avgIntentToPlayCallMs: Double
        public let intentToPlayCallSampleCount: Int

        public init(
            searchCacheHitRate: Double = 0,
            searchCacheHits: Int = 0,
            searchCacheMisses: Int = 0,
            avgSearchMetadataResolveMs: Double = 0,
            searchResolveSampleCount: Int = 0,
            avgPlaybackResolveMs: Double = 0,
            playbackResolveSampleCount: Int = 0,
            warmPlaybackResolveCount: Int = 0,
            coldPlaybackResolveCount: Int = 0,
            avgStartupProxyMs: Double = 0,
            startupCompletedCount: Int = 0,
            startupFailedCount: Int = 0,
            startupCancelledCount: Int = 0,
            fallbackCount: Int = 0,
            stallCount: Int = 0,
            avgIntentToPlayCallMs: Double = 0,
            intentToPlayCallSampleCount: Int = 0
        ) {
            self.searchCacheHitRate = searchCacheHitRate
            self.searchCacheHits = searchCacheHits
            self.searchCacheMisses = searchCacheMisses
            self.avgSearchMetadataResolveMs = avgSearchMetadataResolveMs
            self.searchResolveSampleCount = searchResolveSampleCount
            self.avgPlaybackResolveMs = avgPlaybackResolveMs
            self.playbackResolveSampleCount = playbackResolveSampleCount
            self.warmPlaybackResolveCount = warmPlaybackResolveCount
            self.coldPlaybackResolveCount = coldPlaybackResolveCount
            self.avgStartupProxyMs = avgStartupProxyMs
            self.startupCompletedCount = startupCompletedCount
            self.startupFailedCount = startupFailedCount
            self.startupCancelledCount = startupCancelledCount
            self.fallbackCount = fallbackCount
            self.stallCount = stallCount
            self.avgIntentToPlayCallMs = avgIntentToPlayCallMs
            self.intentToPlayCallSampleCount = intentToPlayCallSampleCount
        }

        /// An all-zero snapshot, for initial view state.
        public static let empty = Snapshot()
    }

    // Search metadata cache
    private var searchCacheHits = 0
    private var searchCacheMisses = 0
    private var searchResolveTimings: [Double] = []

    // Playback stream resolution
    private var playbackResolveTimings: [Double] = []
    private var warmResolveCount = 0
    private var coldResolveCount = 0

    // Playback startup proxy
    private var startupTimings: [Double] = []
    private var startupFailures = 0
    private var startupCancellations = 0

    // Playback failures / fallbacks
    private var fallbacks = 0
    private var stalls = 0

    /// Continuity
    private var intentToPlayCallTimings: [Double] = []

    private let sampleLimit: Int

    /// - Parameter sampleLimit: How many timing samples to keep per domain. Counters are unbounded.
    public init(sampleLimit: Int = 500) {
        self.sampleLimit = max(1, sampleLimit)
    }

    // MARK: - Search metadata cache domain

    /// Records a search-metadata cache lookup. `hit` is the cache outcome; `milliseconds` is the
    /// metadata resolve duration. **This never touches a playback counter.**
    public mutating func recordSearchMetadataCache(hit: Bool, milliseconds: Double) {
        if hit {
            searchCacheHits += 1
        } else {
            searchCacheMisses += 1
        }
        Self.append(milliseconds, to: &searchResolveTimings, limit: sampleLimit)
    }

    // MARK: - Playback stream-resolution domain

    /// Records a playback stream resolution and whether it was warm or cold.
    public mutating func recordPlaybackResolution(path: PlaybackResolutionPath, milliseconds: Double) {
        if path.isWarm {
            warmResolveCount += 1
        } else {
            coldResolveCount += 1
        }
        Self.append(milliseconds, to: &playbackResolveTimings, limit: sampleLimit)
    }

    // MARK: - Playback startup proxy domain

    /// Records a completed first-time-advancing proxy measurement.
    public mutating func recordStartupFirstAdvance(milliseconds: Double) {
        Self.append(milliseconds, to: &startupTimings, limit: sampleLimit)
    }

    /// Records a startup attempt that failed before any advancement.
    public mutating func recordStartupFailure() {
        startupFailures += 1
    }

    /// Records a startup attempt superseded by a newer request or stopped.
    public mutating func recordStartupCancellation() {
        startupCancellations += 1
    }

    // MARK: - Playback failures / fallbacks

    public mutating func recordFallback() {
        fallbacks += 1
    }

    /// Reserved — no producer calls this yet.
    public mutating func recordStall() {
        stalls += 1
    }

    // MARK: - Continuity

    /// Records intent → `engine.play()` return. Neither startup nor first audio.
    public mutating func recordIntentToPlayCall(milliseconds: Double) {
        Self.append(milliseconds, to: &intentToPlayCallTimings, limit: sampleLimit)
    }

    // MARK: - Snapshot

    public mutating func reset() {
        self = PlaybackMetricsAccumulator(sampleLimit: sampleLimit)
    }

    public func snapshot() -> Snapshot {
        let searchTotal = searchCacheHits + searchCacheMisses
        return Snapshot(
            searchCacheHitRate: searchTotal == 0 ? 0 : Double(searchCacheHits) / Double(searchTotal),
            searchCacheHits: searchCacheHits,
            searchCacheMisses: searchCacheMisses,
            avgSearchMetadataResolveMs: average(searchResolveTimings),
            searchResolveSampleCount: searchResolveTimings.count,
            avgPlaybackResolveMs: average(playbackResolveTimings),
            playbackResolveSampleCount: playbackResolveTimings.count,
            warmPlaybackResolveCount: warmResolveCount,
            coldPlaybackResolveCount: coldResolveCount,
            avgStartupProxyMs: average(startupTimings),
            startupCompletedCount: startupTimings.count,
            startupFailedCount: startupFailures,
            startupCancelledCount: startupCancellations,
            fallbackCount: fallbacks,
            stallCount: stalls,
            avgIntentToPlayCallMs: average(intentToPlayCallTimings),
            intentToPlayCallSampleCount: intentToPlayCallTimings.count
        )
    }

    // MARK: - Private

    /// Static so the inout buffer never overlaps access to `self`.
    private static func append(_ value: Double, to samples: inout [Double], limit: Int) {
        guard value.isFinite else { return }
        samples.append(value)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    private func average(_ samples: [Double]) -> Double {
        samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
    }
}
