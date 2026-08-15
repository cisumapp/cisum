//
//  PlayerViewModel.swift
//  Player
//
//  Coordinates the playback components. Implements none of them.
//

import Foundation
import Models
import Observation
import PlaybackCore
import ProviderSDK
import SwiftUI
import Utilities

/// Wires the playback components together and exposes commands to the UI.
///
/// The previous `PlayerViewModel` was 1,794 lines plus seven extensions, and *implemented* queue
/// management, search, result scoring, stream resolution, quality ranking, artwork processing,
/// lyrics aggregation, and provider-specific branching. This one owns none of that. It holds
/// references, forwards calls, and keeps the published state objects in step.
///
/// State lives on the four objects from `Models`, split by update frequency rather than by
/// feature, so a 30 Hz position tick does not invalidate the whole player UI. See
/// `PlayerState.swift`.
@MainActor
@Observable
public final class PlayerViewModel: PlaybackCommands {
    // MARK: Published state

    public let nowPlaying: NowPlayingState
    public let transport: TransportState
    public let progress: ProgressState
    public let lyrics: LyricsPresentation

    // MARK: Components

    public let queue: PlaybackQueue

    /// Whether the queue sheet is showing. Pure UI state, owned here because the player's own
    /// chrome toggles it from more than one place.
    public var isQueueVisible = false
    private let engine: PlaybackEngine
    private let resolver: PlaybackResolver
    private var nowPlayingCenter: NowPlayingCenter?

    /// Reports tap-to-play and cache-hit rates. Compared against the pre-reset baseline.
    private let metrics: PlaybackMetricsStore

    /// Guards against an in-flight resolve for a track the user has already skipped past.
    private var loadTask: Task<Void, Never>?

    public init(
        sources: SourceRegistry,
        metrics: PlaybackMetricsStore = .shared
    ) {
        let nowPlaying = NowPlayingState()
        let transport = TransportState()
        let progress = ProgressState()

        self.nowPlaying = nowPlaying
        self.transport = transport
        self.progress = progress
        self.lyrics = LyricsPresentation()
        self.queue = PlaybackQueue()
        self.engine = PlaybackEngine(progress: progress, transport: transport)
        self.resolver = PlaybackResolver(sources: sources)
        self.metrics = metrics

        AudioSession.configure()
        wireEngineCallbacks()

        let center = NowPlayingCenter(commands: self)
        center.registerCommands()
        self.nowPlayingCenter = center
    }

    // MARK: - PlaybackCommands

    public func togglePlayPause() {
        engine.togglePlayPause()
        publishNowPlaying()
    }

    public func skipToNext() {
        guard let next = queue.advance() else {
            engine.stop()
            nowPlaying.ref = nil
            nowPlayingCenter?.clear()
            return
        }
        start(next)
    }

    public func skipToPrevious() {
        // Restart the current track when more than a few seconds in — what every music player does,
        // and what users expect from a double-tap on headphones.
        if progress.currentTime > 3 {
            engine.seek(to: 0)
            return
        }
        guard let previous = queue.retreat() else { return }
        start(previous)
    }

    public func seek(to timestamp: Double) {
        engine.seek(to: timestamp)
        publishNowPlaying()
    }

    public func cyclePlaybackMode() {
        queue.cycleMode()
        transport.playbackMode = queue.mode
        updateSkipAvailability()
    }

    public func load(_ ref: PlayableRef, preserveQueue: Bool) {
        queue.play(ref, preserveQueue: preserveQueue)
        start(ref)
    }

    public func setQueue(_ refs: [PlayableRef], startIndex: Int, shuffled: Bool) {
        queue.replace(with: refs, startIndex: startIndex, shuffled: shuffled)
        transport.playbackMode = queue.mode
        guard let current = queue.current else { return }
        start(current)
    }

    // MARK: - Playback

    /// Begins playing a ref: show its metadata immediately, resolve audio in the background.
    ///
    /// The display fields are painted from the ref before any network work, so tapping a track
    /// updates the UI instantly even when resolution takes a moment.
    private func start(_ ref: PlayableRef) {
        loadTask?.cancel()

        nowPlaying.ref = ref
        nowPlaying.title = ref.title
        nowPlaying.artist = ref.artist
        nowPlaying.artworkURL = ref.artworkURL
        nowPlaying.duration = ref.durationSeconds ?? 0
        transport.isBuffering = true
        progress.currentTime = 0
        updateSkipAvailability()
        publishNowPlaying()

        let started = ContinuousClock.now

        loadTask = Task { [weak self] in
            guard let self else { return }
            let span = CisumSignpost.playback.begin("tap-to-play", ref.title)
            defer { CisumSignpost.playback.end("tap-to-play", state: span) }

            do {
                let stream = try await resolver.resolve(ref)
                guard !Task.isCancelled, nowPlaying.ref == ref else { return }

                AudioSession.activate()
                engine.play(url: stream.url)
                publishNowPlaying()

                let elapsed = started.duration(to: .now)
                let milliseconds = Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1e15
                await metrics.recordTapToPlay(milliseconds: milliseconds)
            } catch {
                guard !Task.isCancelled, nowPlaying.ref == ref else { return }
                transport.isBuffering = false
                transport.isPlaying = false
                PerfLog.error("Could not play \(ref.title): \(error.localizedDescription)")
            }
        }
    }

    private func wireEngineCallbacks() {
        engine.onPlaybackEnded = { [weak self] in
            self?.skipToNext()
        }
        engine.onPlaybackFailed = { [weak self] _ in
            // A failure here is overwhelmingly an expired CDN URL rather than a dead track, so the
            // right response is to drop the cached URL and try the same ref again. Advancing the
            // queue on the first failure is what made tracks appear to skip themselves.
            self?.retryCurrentAfterFailure()
        }
    }

    private var hasRetriedCurrent = false

    private func retryCurrentAfterFailure() {
        guard let ref = nowPlaying.ref else { return }

        guard !hasRetriedCurrent else {
            // Already retried with a fresh URL and it still failed; the track is genuinely
            // unplayable, so move on rather than looping.
            hasRetriedCurrent = false
            skipToNext()
            return
        }

        hasRetriedCurrent = true
        invalidateCachedStream?(ref)
        start(ref)
    }

    /// Drops the persisted stream URL for a ref after a playback failure.
    ///
    /// Injected rather than reached for directly, because persistence is the application's concern
    /// and Player does not import SwiftData.
    public var invalidateCachedStream: (@MainActor (PlayableRef) -> Void)?

    // MARK: - Wiring for the composition root

    /// Supplies the persistence hooks the resolver needs.
    ///
    /// Player deliberately does not know about SwiftData; the app answers these two questions.
    public func configurePersistence(
        lookup: @escaping @MainActor (PlayableRef) -> SongSource?,
        persist: @escaping @MainActor (PlayableRef, SourceTrack, SourceStream) -> Void,
        invalidate: @escaping @MainActor (PlayableRef) -> Void
    ) {
        resolver.lookup = lookup
        resolver.persist = persist
        invalidateCachedStream = invalidate
    }

    // MARK: - Lifecycle

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background else { return }
        PlaybackControlSettings.shared.flushPendingWrites()
    }

    // MARK: - Private

    private func updateSkipAvailability() {
        transport.canSkipForward = queue.canSkipForward
        transport.canSkipBackward = queue.canSkipBackward
        nowPlayingCenter?.updateAvailability(
            canSkipForward: queue.canSkipForward,
            canSkipBackward: queue.canSkipBackward
        )
    }

    private func publishNowPlaying() {
        nowPlayingCenter?.update(
            nowPlaying: nowPlaying,
            transport: transport,
            currentTime: progress.currentTime
        )
    }
}
