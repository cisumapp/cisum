//
//  PlaybackMetricsStore.swift
//  Player
//
//  The numbers the architecture reset is measured against.
//

import Foundation

/// Records playback timings so the rewrite can be proven faster rather than assumed faster.
///
/// The headline metric is **tap-to-play**: from the user's tap to the first audio frame. The
/// pre-reset baseline in `docs/superpowers/baselines/` is what these are compared against.
///
/// `cacheHitRate` matters most for judging the architecture specifically. It is the fraction of
/// plays served from a cached stream URL with no network call at all — the fast path that was
/// impossible before, because a queue entry carried a resolver closure rather than an identity.
/// If it stays near zero in real use, the `SongSource` binding is not being persisted or the
/// expiry policy is wrong.
public actor PlaybackMetricsStore {
    public static let shared = PlaybackMetricsStore()

    private var resolveTimings: [Double] = []
    private var tapToPlayTimings: [Double] = []
    private var cacheHits = 0
    private var cacheMisses = 0
    private var stalls = 0

    /// Keeps memory bounded during a long session; the medians stay representative.
    private let sampleLimit = 500

    public init() {}

    public func recordResolve(milliseconds: Double) {
        append(milliseconds, to: &resolveTimings)
    }

    public func recordTapToPlay(milliseconds: Double) {
        append(milliseconds, to: &tapToPlayTimings)
    }

    public func recordCacheHit() {
        cacheHits += 1
    }

    public func recordCacheMiss() {
        cacheMisses += 1
    }

    public func recordStall() {
        stalls += 1
    }

    public func reset() {
        resolveTimings = []
        tapToPlayTimings = []
        cacheHits = 0
        cacheMisses = 0
        stalls = 0
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            cacheHitRate: cacheHits + cacheMisses == 0
                ? 0
                : Double(cacheHits) / Double(cacheHits + cacheMisses),
            avgResolveMs: average(resolveTimings),
            avgTapToPlayMs: average(tapToPlayTimings),
            resolveSampleCount: resolveTimings.count,
            tapToPlaySampleCount: tapToPlayTimings.count,
            totalStallCount: stalls
        )
    }

    /// A point-in-time view of the metrics, for the diagnostics screen.
    public struct Snapshot: Sendable, Equatable {
        public let cacheHitRate: Double
        public let avgResolveMs: Double
        public let avgTapToPlayMs: Double
        public let resolveSampleCount: Int
        public let tapToPlaySampleCount: Int
        public let totalStallCount: Int

        public init(
            cacheHitRate: Double = 0,
            avgResolveMs: Double = 0,
            avgTapToPlayMs: Double = 0,
            resolveSampleCount: Int = 0,
            tapToPlaySampleCount: Int = 0,
            totalStallCount: Int = 0
        ) {
            self.cacheHitRate = cacheHitRate
            self.avgResolveMs = avgResolveMs
            self.avgTapToPlayMs = avgTapToPlayMs
            self.resolveSampleCount = resolveSampleCount
            self.tapToPlaySampleCount = tapToPlaySampleCount
            self.totalStallCount = totalStallCount
        }
    }

    private func append(_ value: Double, to samples: inout [Double]) {
        samples.append(value)
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
    }

    private func average(_ samples: [Double]) -> Double {
        samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
    }
}
