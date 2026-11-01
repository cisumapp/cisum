//
//  PlaybackMetricsTests.swift
//  PlaybackCoreTests
//
//  Pass 2.7: the startup proxy tracker, the first-advance condition, metric-domain isolation, and
//  warm/cold playback-resolution classification.
//

import Foundation
import Models
@testable import PlaybackCore
import ProviderSDK
import Testing

// MARK: - Startup proxy tracker

@MainActor
private final class FakeClock {
    var instant: ContinuousClock.Instant = .now
    func advance(milliseconds: Int) {
        instant = instant.advanced(by: .milliseconds(milliseconds))
    }
}

@MainActor
@Suite("Startup proxy tracker (first-time-advancing)")
struct PlaybackStartupTrackerTests {
    @Test("a request completes exactly once")
    func completesExactlyOnce() {
        let clock = FakeClock()
        var tracker = PlaybackStartupTracker(now: { clock.instant })
        tracker.begin(requestID: 1)
        clock.advance(milliseconds: 250)

        #expect(tracker.completeFirstAdvance(requestID: 1) == .firstAdvance(.init(requestID: 1, milliseconds: 250)))
        // A second advancement for the same request records nothing.
        #expect(tracker.completeFirstAdvance(requestID: 1) == nil)
        #expect(!tracker.hasPendingMeasurement)
    }

    @Test("completion requires a matching pending request")
    func unknownOrStaleRequestRecordsNothing() {
        var tracker = PlaybackStartupTracker(now: { ContinuousClock.now })
        // Nothing started yet.
        #expect(tracker.completeFirstAdvance(requestID: 7) == nil)
        tracker.begin(requestID: 1)
        // A stale callback for a different request must not complete the pending one.
        #expect(tracker.completeFirstAdvance(requestID: 2) == nil)
        #expect(tracker.hasPendingMeasurement)
    }

    @Test("a new request supersedes and cancels the previous one")
    func supersedeCancelsPrevious() {
        let clock = FakeClock()
        var tracker = PlaybackStartupTracker(now: { clock.instant })
        tracker.begin(requestID: 1)

        let second = tracker.begin(requestID: 2)
        #expect(second.superseded == .cancelled(requestID: 1))
        // The superseded request can no longer complete.
        #expect(tracker.completeFirstAdvance(requestID: 1) == nil)

        clock.advance(milliseconds: 40)
        #expect(tracker.completeFirstAdvance(requestID: 2) == .firstAdvance(.init(requestID: 2, milliseconds: 40)))
    }

    @Test("rapid successive requests each report the prior as cancelled")
    func rapidSuccession() {
        var tracker = PlaybackStartupTracker(now: { ContinuousClock.now })
        tracker.begin(requestID: 1)
        #expect(tracker.begin(requestID: 2).superseded == .cancelled(requestID: 1))
        #expect(tracker.begin(requestID: 3).superseded == .cancelled(requestID: 2))
        #expect(tracker.hasPendingMeasurement)
    }

    @Test("failure, cancellation and success are distinguishable")
    func outcomesAreDistinguishable() {
        var tracker = PlaybackStartupTracker(now: { ContinuousClock.now })

        tracker.begin(requestID: 1)
        #expect(tracker.fail(requestID: 1) == .failed(requestID: 1))
        // A failure terminated the request: no completion can follow.
        #expect(tracker.completeFirstAdvance(requestID: 1) == nil)

        tracker.begin(requestID: 2)
        #expect(tracker.cancel(requestID: 2) == .cancelled(requestID: 2))
        #expect(!tracker.hasPendingMeasurement)

        // Failing or cancelling a request that is not pending records nothing.
        #expect(tracker.fail(requestID: 99) == nil)
        #expect(tracker.cancel(requestID: 99) == nil)
    }
}

// MARK: - First-advance condition

@Suite("First-advance detection")
struct FirstAdvanceDetectorTests {
    @Test("only an advancing, playing, unreported sample qualifies")
    func condition() {
        #expect(!FirstAdvanceDetector.qualifies(seconds: 0, isPlaying: true, alreadyReported: false))
        #expect(!FirstAdvanceDetector.qualifies(seconds: -1, isPlaying: true, alreadyReported: false))
        #expect(!FirstAdvanceDetector.qualifies(seconds: 0.25, isPlaying: false, alreadyReported: false))
        #expect(!FirstAdvanceDetector.qualifies(seconds: 0.25, isPlaying: true, alreadyReported: true))
        #expect(!FirstAdvanceDetector.qualifies(seconds: .nan, isPlaying: true, alreadyReported: false))
        #expect(FirstAdvanceDetector.qualifies(seconds: 0.25, isPlaying: true, alreadyReported: false))
    }
}

// MARK: - Metric-domain isolation

@Suite("Metric domain isolation")
struct PlaybackMetricsAccumulatorTests {
    @Test("a search cache event never touches a playback counter")
    func searchDomainIsIsolated() {
        var accumulator = PlaybackMetricsAccumulator()
        accumulator.recordSearchMetadataCache(hit: true, milliseconds: 12)
        accumulator.recordSearchMetadataCache(hit: false, milliseconds: 30)

        let snapshot = accumulator.snapshot()
        #expect(snapshot.searchCacheHits == 1)
        #expect(snapshot.searchCacheMisses == 1)
        #expect(snapshot.searchCacheHitRate == 0.5)
        #expect(snapshot.searchResolveSampleCount == 2)

        // The playback domains must be untouched.
        #expect(snapshot.warmPlaybackResolveCount == 0)
        #expect(snapshot.coldPlaybackResolveCount == 0)
        #expect(snapshot.playbackResolveSampleCount == 0)
        #expect(snapshot.avgPlaybackResolveMs == 0)
        #expect(snapshot.startupCompletedCount == 0)
        #expect(snapshot.intentToPlayCallSampleCount == 0)
    }

    @Test("playback resolutions are counted warm and cold, and not as search events")
    func playbackClassificationIsIsolated() {
        var accumulator = PlaybackMetricsAccumulator()
        accumulator.recordPlaybackResolution(path: .cachedStreamURL, milliseconds: 1)
        accumulator.recordPlaybackResolution(path: .directProviderID, milliseconds: 200)
        accumulator.recordPlaybackResolution(path: .matchedProvider, milliseconds: 400)

        let snapshot = accumulator.snapshot()
        #expect(snapshot.warmPlaybackResolveCount == 1)
        #expect(snapshot.coldPlaybackResolveCount == 2)
        #expect(snapshot.playbackResolveSampleCount == 3)
        #expect(snapshot.avgPlaybackResolveMs == 200.33333333333334) // (1 + 200 + 400) / 3

        // No search or startup metric is affected.
        #expect(snapshot.searchCacheHits == 0)
        #expect(snapshot.searchCacheMisses == 0)
        #expect(snapshot.startupCompletedCount == 0)
    }

    @Test("startup outcomes are separate from resolve, search and continuity counters")
    func startupDomainIsIsolated() {
        var accumulator = PlaybackMetricsAccumulator()
        accumulator.recordStartupFirstAdvance(milliseconds: 300)
        accumulator.recordStartupFirstAdvance(milliseconds: 500)
        accumulator.recordStartupFailure()
        accumulator.recordStartupCancellation()
        accumulator.recordFallback()
        accumulator.recordIntentToPlayCall(milliseconds: 120)

        let snapshot = accumulator.snapshot()
        #expect(snapshot.startupCompletedCount == 2)
        #expect(snapshot.avgStartupProxyMs == 400)
        #expect(snapshot.startupFailedCount == 1)
        #expect(snapshot.startupCancelledCount == 1)
        #expect(snapshot.fallbackCount == 1)
        #expect(snapshot.intentToPlayCallSampleCount == 1)
        #expect(snapshot.avgIntentToPlayCallMs == 120)

        #expect(snapshot.playbackResolveSampleCount == 0)
        #expect(snapshot.searchResolveSampleCount == 0)
    }

    @Test("reset clears every domain")
    func resetClearsAllDomains() {
        var accumulator = PlaybackMetricsAccumulator()
        accumulator.recordSearchMetadataCache(hit: true, milliseconds: 10)
        accumulator.recordPlaybackResolution(path: .cachedStreamURL, milliseconds: 1)
        accumulator.recordStartupFirstAdvance(milliseconds: 100)
        accumulator.recordStartupFailure()

        accumulator.reset()

        let snapshot = accumulator.snapshot()
        #expect(snapshot == .empty)
    }
}

// MARK: - Warm/cold resolution classification (resolver integration)

private struct FakeSource: MusicSource {
    let id: String
    let capabilities: SourceCapability
    let streams: [SourceStream]

    var displayName: String {
        id
    }

    func searchTracks(query _: String, limit _: Int) async throws -> [SourceTrack] {
        []
    }

    func stream(trackID _: String, quality _: QualityHint) async throws -> SourceStream {
        if let first = streams.first {
            return first
        }
        throw SourceError.unsupported(source: id, operation: "stream")
    }

    func streamCandidates(trackID _: String, quality _: QualityHint) async throws -> [SourceStream] {
        streams
    }
}

@MainActor
@Suite("Playback resolution warm/cold classification")
struct PlaybackResolutionClassificationTests {
    private func ref() -> PlayableRef {
        PlayableRef(
            songID: "s",
            sourceID: "youtube",
            sourceTrackID: "v1",
            title: "Ivy",
            artist: "Frank Ocean",
            durationSeconds: 249
        )
    }

    @Test("a fresh cached binding resolves warm")
    func warmResolution() async throws {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "v1")
        try binding.cacheStream(
            url: #require(URL(string: "https://cdn.example.com/a.m4a")),
            mimeType: "audio/mp4",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let resolver = PlaybackResolver(sources: SourceRegistry())
        resolver.bindings = { _ in [binding] }
        var paths: [PlaybackResolutionPath] = []
        resolver.onResolveOutcome = { path, _ in paths.append(path) }

        let streams = try await resolver.resolve(ref())
        #expect(!streams.isEmpty)
        #expect(paths == [.cachedStreamURL])
    }

    @Test("resolving by a known provider id resolves cold")
    func coldDirectResolution() async throws {
        let source = try FakeSource(
            id: "youtube",
            capabilities: [.stream],
            streams: [SourceStream(url: #require(URL(string: "https://cdn.example.com/b.m4a")), kind: .direct)]
        )
        let resolver = PlaybackResolver(sources: SourceRegistry(sources: [source]))
        resolver.bindings = { _ in [] }
        var paths: [PlaybackResolutionPath] = []
        resolver.onResolveOutcome = { path, _ in paths.append(path) }

        _ = try await resolver.resolve(ref())
        #expect(paths == [.directProviderID])
    }

    @Test("an expired cached URL is a cold resolve, not a warm one")
    func expiredBindingResolvesCold() async throws {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "v1")
        try binding.cacheStream(
            url: #require(URL(string: "https://cdn.example.com/c.m4a")),
            mimeType: "audio/mp4",
            expiresAt: Date().addingTimeInterval(-60)
        )
        let source = try FakeSource(
            id: "youtube",
            capabilities: [.stream],
            streams: [SourceStream(url: #require(URL(string: "https://cdn.example.com/d.m4a")), kind: .direct)]
        )
        let resolver = PlaybackResolver(sources: SourceRegistry(sources: [source]))
        resolver.bindings = { _ in [binding] }
        var paths: [PlaybackResolutionPath] = []
        resolver.onResolveOutcome = { path, _ in paths.append(path) }

        _ = try await resolver.resolve(ref())
        #expect(paths == [.directProviderID])
        #expect(!PlaybackResolutionPath.directProviderID.isWarm)
        #expect(PlaybackResolutionPath.cachedStreamURL.isWarm)
    }
}
