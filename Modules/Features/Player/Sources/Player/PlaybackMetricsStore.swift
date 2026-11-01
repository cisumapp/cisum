//
//  PlaybackMetricsStore.swift
//  Player
//
//  Thread-safe access to the playback/search metrics.
//

import Foundation
import PlaybackCore

/// The app-wide metrics store.
///
/// This actor owns no metric semantics. Every definition — which domain a number belongs to and what
/// it measures — lives in `PlaybackMetricsAccumulator` (`PlaybackCore`), which is pure and therefore
/// testable. This type only serialises access to a single accumulator instance.
///
/// **One number is not a startup metric.** `recordIntentToPlayCall` measures intent →
/// `PlaybackEngine.play()` returning. That is neither startup nor audible audio; it is kept only so
/// the number the app used to display has a truthful name and a documented boundary. The startup
/// signal is `recordStartupFirstAdvance` — the first-time-advancing proxy (see
/// `PlaybackStartupTracker`), which is also **not** proof of audible output.
public actor PlaybackMetricsStore {
    public static let shared = PlaybackMetricsStore()

    /// The point-in-time metrics view, re-exported so callers need only this type.
    public typealias Snapshot = PlaybackMetricsAccumulator.Snapshot

    private var accumulator = PlaybackMetricsAccumulator()

    /// The stream playback is using, for the diagnostics surfaces.
    ///
    /// Lives here rather than in a new app-wide observable because Settings already reads this
    /// store and the player already writes it; a second shared object would be a second source of
    /// truth for the same fact. It is **not** cleared by `reset()` — that clears measurements, and
    /// what is playing is not a measurement.
    private var activeStream: ActiveStreamState = .idle

    public init() {}

    // MARK: - Search metadata cache domain

    /// A `VideoMetadataCache` lookup: the cache outcome and the metadata resolve duration.
    /// Never touches a playback counter.
    public func recordSearchMetadataCache(hit: Bool, milliseconds: Double) {
        accumulator.recordSearchMetadataCache(hit: hit, milliseconds: milliseconds)
    }

    // MARK: - Playback stream-resolution domain

    /// A playback stream resolution, classified warm/cold by `PlaybackResolutionPath`.
    public func recordPlaybackResolution(path: PlaybackResolutionPath, milliseconds: Double) {
        accumulator.recordPlaybackResolution(path: path, milliseconds: milliseconds)
    }

    // MARK: - Playback startup proxy domain

    /// A completed first-time-advancing proxy measurement.
    public func recordStartupFirstAdvance(milliseconds: Double) {
        accumulator.recordStartupFirstAdvance(milliseconds: milliseconds)
    }

    /// A startup attempt that failed before any advancement.
    public func recordStartupFailure() {
        accumulator.recordStartupFailure()
    }

    /// A startup attempt superseded by a newer request, or stopped.
    public func recordStartupCancellation() {
        accumulator.recordStartupCancellation()
    }

    // MARK: - Playback failures / fallbacks

    public func recordFallback() {
        accumulator.recordFallback()
    }

    /// Reserved — no producer records a stall yet.
    public func recordStall() {
        accumulator.recordStall()
    }

    // MARK: - Continuity

    /// Intent → `engine.play()` return. Neither startup nor first audio.
    public func recordIntentToPlayCall(milliseconds: Double) {
        accumulator.recordIntentToPlayCall(milliseconds: milliseconds)
    }

    // MARK: - Active stream (diagnostics)

    /// Records the stream playback is now using, or the reason there is none.
    public func recordActiveStream(_ state: ActiveStreamState) {
        activeStream = state
    }

    /// The stream playback is using. Reported from `PlaybackEngine`'s actual session, never from
    /// the requested track.
    public func currentActiveStream() -> ActiveStreamState {
        activeStream
    }

    // MARK: - Diagnostics

    public func snapshot() -> Snapshot {
        accumulator.snapshot()
    }

    public func reset() {
        accumulator.reset()
    }
}
