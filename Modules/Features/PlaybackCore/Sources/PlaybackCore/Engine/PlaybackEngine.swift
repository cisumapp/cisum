//
//  PlaybackEngine.swift
//  Player
//
//  The single AVPlayer owner. Nothing else in the package creates one.
//

import AVFoundation
import Foundation
import Models
import ProviderSDK
import Utilities

/// Drives `AVPlayer`. Knows about audio, not about music.
///
/// This is the whole of cisum's interaction with `AVFoundation`: one player, one place that
/// configures the audio session, one place that observes item status. The previous implementation
/// configured the audio session in two separate files and spread item observation across the view
/// model and three of its extensions.
///
/// It takes a URL and plays it. Deciding *which* URL — matching, quality selection, provider
/// choice — happens before anything gets here.
@MainActor
@Observable
public final class PlaybackEngine {
    /// The one and only `AVPlayer`.
    public private(set) var player = AVPlayer()

    /// Published position, driven by the periodic time observer.
    public let progress: ProgressState

    /// Published transport state.
    public let transport: TransportState

    /// Fires when the current item plays to its end, so the queue can advance.
    public var onPlaybackEnded: (@MainActor () -> Void)?

    /// Fires when the current item fails, carrying the reason.
    ///
    /// The caller decides what to do — usually invalidate the cached stream URL and re-resolve,
    /// since the overwhelmingly common cause is an expired CDN URL rather than a dead track.
    public var onPlaybackFailed: (@MainActor (Error) -> Void)?

    /// Fires when an item finishes loading and is ready to play.
    ///
    /// Carries the item so the caller can read `duration` for the scrubber when search metadata
    /// lacked a parseable timestamp (common with YouTube Music results).
    public var onReadyForPlayback: (@MainActor (AVPlayerItem) -> Void)?

    /// Fires on every periodic time tick (4 Hz) with the position in seconds.
    ///
    /// For listeners that need the clock but must not observe `ProgressState` — the lyric-line
    /// index, which changes about once a line rather than once a tick.
    public var onTick: (@MainActor (Double) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    /// Whether the current item has started playing. A stall before that is a slow start, not a
    /// stall mid-playback (and not the end of the data).
    private var hasAdvanced = false

    public init(progress: ProgressState, transport: TransportState) {
        self.progress = progress
        self.transport = transport
        observeTimeUpdates()
    }

    // MARK: - Transport

    /// Loads a stream and begins playback.
    ///
    /// Takes the whole `SourceStream` rather than a bare URL because the headers are not optional
    /// extra: a googlevideo URL is signed for one client and the CDN checks the User-Agent. Losing
    /// them is silent — nothing throws, AVFoundation only logs `CRABS ... ReadError`, and the
    /// player sits at 0:00 looking paused.
    public func play(_ stream: SourceStream) {
        let asset = stream.headers.isEmpty
            ? AVURLAsset(url: stream.url)
            : AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])

        let item = AVPlayerItem(asset: asset)
        // Both of these existed on the old engine and were lost. The buffer duration is what makes
        // playback start promptly instead of after a full prefetch.
        item.preferredForwardBufferDuration = 2.0
        // End where the service says the file ends. AVFoundation estimates a fragmented MP4's length
        // (measured at up to twice the real one), so the item never reached its *own* end: the clock
        // ran on past the last byte, no did-play-to-end arrived, and the queue never advanced.
        if let duration = stream.durationSeconds, duration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: duration, preferredTimescale: 600)
        }
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        observe(item)

        player.replaceCurrentItem(with: item)
        player.play()
        transport.isPlaying = true
    }

    public func resume() {
        player.play()
        transport.isPlaying = true
    }

    public func pause() {
        player.pause()
        transport.isPlaying = false
    }

    public func togglePlayPause() {
        if transport.isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        progress.currentTime = seconds
    }

    public func stop() {
        player.pause()
        // Observers are torn down *before* the item is detached. `replaceCurrentItem(with: nil)` can
        // make the outgoing item report a failure, and a stopped player has no current item to fail.
        removeItemObservers()
        player.replaceCurrentItem(with: nil)
        transport.isPlaying = false
        transport.isBuffering = false
        progress.currentTime = 0
        hasAdvanced = false
    }

    // MARK: - Observation

    /// One periodic observer for the lifetime of the engine.
    ///
    /// Writes only to `ProgressState`, which nothing but the scrubber observes. That isolation is
    /// what keeps a 30 Hz tick from invalidating the entire player UI — see `PlayerState.swift`.
    private func observeTimeUpdates() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress.currentTime = time.seconds
                self.onTick?(time.seconds)
                if time.seconds > 0, self.player.timeControlStatus == .playing {
                    self.hasAdvanced = true
                }
                self.clearBufferingIfRecovered()
            }
        }
    }

    /// Clears the buffering flag once the current item is rendering again.
    ///
    /// Without this the flag set by a stall would stay on until the next track, which is worse than
    /// not reporting the stall at all.
    private func clearBufferingIfRecovered() {
        guard transport.isBuffering, player.timeControlStatus == .playing else { return }
        transport.isBuffering = false
    }

    private func observe(_ item: AVPlayerItem) {
        // Nothing observed for the outgoing item survives: an item that is no longer current must not
        // be able to report an end, a failure or a stall.
        removeItemObservers()

        hasAdvanced = false

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(item) else { return }
                self.onPlaybackEnded?()
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(item) else { return }
                // A stall before the item ever advanced is a slow start, not a stall mid-playback.
                guard self.hasAdvanced else { return }
                // A stall in the last seconds before the stated end is the end of the data: the
                // stated length runs a fraction past the last audio sample, so playback waits there
                // for bytes that do not exist and `forwardPlaybackEndTime` is never reached.
                if let item, item.forwardPlaybackEndTime.isNumeric,
                   self.player.currentTime().seconds >= item.forwardPlaybackEndTime.seconds - 2
                {
                    self.onPlaybackEnded?()
                    return
                }
                self.transport.isBuffering = true
                PerfLog.warning("Playback stalled; waiting for more data")
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(item) else { return }
                switch item.status {
                case .readyToPlay:
                    self.transport.isBuffering = false
                    self.onReadyForPlayback?(item)
                case .failed:
                    self.transport.isBuffering = false
                    self.transport.isPlaying = false
                    let error = item.error ?? PlaybackError.unknown
                    // AVFoundation reports most stream failures as -11800 "unknown error"; the cause
                    // (an OSStatus such as -12660 for HTTP 403) is only in the underlying error and the
                    // item's error log, so both are logged. Host only — the URL is a signed credential.
                    let ns = error as NSError
                    let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain) \($0.code)" } ?? "none"
                    let event = item.errorLog()?.events.last
                    PerfLog.error(
                        "Playback failed: \(ns.domain) \(ns.code) underlying=\(underlying)"
                            + " http=\(event?.errorStatusCode ?? 0) \(event?.errorDomain ?? "")"
                            + " \(event?.errorComment ?? "") host=\((item.asset as? AVURLAsset)?.url.host ?? "?")"
                    )
                    self.onPlaybackFailed?(error)
                default:
                    self.transport.isBuffering = true
                }
            }
        }
    }

    /// Whether an event for `item` still belongs to the item playback is using.
    ///
    /// The observers are created per item, but an item can be detached *while it is still loading* —
    /// by `stop()`, or by a replacement racing that item's first `readyToPlay` — and a detached item
    /// still reports its status and its failures. Without this check an outgoing item's late failure
    /// is indistinguishable from the current item failing: it would re-resolve the track the user
    /// just asked for, or write a duration for a track that is no longer playing.
    private func isCurrent(_ item: AVPlayerItem?) -> Bool {
        PlaybackItemScope.isCurrent(eventItem: item, currentItem: player.currentItem)
    }

    private func removeItemObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
    }

    /// Tears down observers.
    ///
    /// Explicit rather than in `deinit`: this type is `@MainActor`, and `deinit` is nonisolated, so
    /// it cannot touch the stored observers at all. The owner calls this when playback is finished
    /// with — which is also the only point at which teardown ordering is actually knowable.
    public func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        stop()
    }
}

/// Whether a player-item event belongs to the item playback is using.
///
/// A value type with one pure function, separated from `PlaybackEngine` so the rule that makes the
/// item-scoped callbacks safe is testable without a running player. It is the guard behind three
/// requirements at once: an outgoing item's failure cannot disturb newer playback, an outgoing
/// item's readiness cannot rewrite the current timeline, and a stall is only ever reported for the
/// item that is actually playing.
enum PlaybackItemScope {
    static func isCurrent(eventItem: AVPlayerItem?, currentItem: AVPlayerItem?) -> Bool {
        guard let eventItem, let currentItem else { return false }
        return eventItem === currentItem
    }
}

public enum PlaybackError: Error, LocalizedError {
    case unknown

    public var errorDescription: String? {
        switch self {
        case .unknown: "Playback failed for an unknown reason."
        }
    }
}
