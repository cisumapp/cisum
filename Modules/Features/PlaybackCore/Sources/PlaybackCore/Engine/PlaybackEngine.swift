//
//  PlaybackEngine.swift
//  Player
//
//  The single AVPlayer owner. Nothing else in the package creates one.
//

import AVFoundation
import Foundation
import Models
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

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    public init(progress: ProgressState, transport: TransportState) {
        self.progress = progress
        self.transport = transport
        observeTimeUpdates()
    }

    // MARK: - Transport

    /// Loads a URL and begins playback.
    ///
    /// - Parameter headers: Some providers require a `User-Agent` or `Referer` on the media
    ///   request itself, not just on the API call that produced the URL.
    public func play(url: URL, headers: [String: String] = [:]) {
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])

        let item = AVPlayerItem(asset: asset)
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
        transport.isPlaying ? pause() : resume()
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
        player.replaceCurrentItem(with: nil)
        transport.isPlaying = false
        progress.currentTime = 0
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
                self?.progress.currentTime = time.seconds
            }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        endObserver.map(NotificationCenter.default.removeObserver)
        statusObservation?.invalidate()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onPlaybackEnded?()
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.transport.isBuffering = false
                case .failed:
                    self.transport.isBuffering = false
                    self.transport.isPlaying = false
                    let error = item.error ?? PlaybackError.unknown
                    PerfLog.error("Playback failed: \(error.localizedDescription)")
                    self.onPlaybackFailed?(error)
                default:
                    self.transport.isBuffering = true
                }
            }
        }
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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        stop()
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
