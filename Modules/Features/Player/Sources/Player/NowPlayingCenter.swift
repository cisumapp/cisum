//
//  NowPlayingCenter.swift
//  Player
//
//  Lock screen, Control Centre, and hardware transport controls. One place.
//

import Aesthetics
import AVFoundation
import Foundation
import Kingfisher
import MediaPlayer
import Models
import Utilities

/// Publishes now-playing info and handles remote commands.
///
/// It watches the player's state rather than being told when to publish. The old version was
/// called by hand from every command, so a path that forgot (restarting a track from the
/// headphones) left the lock screen behind, and one that called too early (seek, before the
/// engine had moved) published the old position.
@MainActor
public final class NowPlayingCenter {
    private let commands: any PlaybackCommands
    private let nowPlaying: NowPlayingState
    private let transport: TransportState
    private let progress: ProgressState
    private var registered = false

    /// The cover, decoded once per URL.
    private var artwork: (url: URL, value: MPMediaItemArtwork)?
    private var artworkTask: Task<Void, Never>?
    /// The track's looping video (Spotify Canvas or Apple Music motion artwork) and its shape.
    private var motion: (ref: PlayableRef, video: URL, isSquare: Bool)?
    /// What the lock screen was last told, so it can extrapolate the clock and spot a jump.
    private var published: (time: Double, at: Date, rate: Double)?

    public init(
        commands: any PlaybackCommands,
        nowPlaying: NowPlayingState,
        transport: TransportState,
        progress: ProgressState
    ) {
        self.commands = commands
        self.nowPlaying = nowPlaying
        self.transport = transport
        self.progress = progress
        observeTrack()
        observeClock()
    }

    // MARK: - Observation

    /// Everything the lock screen shows except the clock.
    private func observeTrack() {
        withObservationTracking {
            _ = (nowPlaying.ref, nowPlaying.title, nowPlaying.artist, nowPlaying.artworkURL, nowPlaying.timelineDuration)
            _ = (transport.isPlaying, transport.isBuffering, transport.canSkipForward, transport.canSkipBackward)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.observeTrack()
            }
        }
    }

    /// The clock ticks four times a second, and the lock screen runs its own from the last rate
    /// and position, so it is only corrected when the two disagree: a seek, a restart, a stall.
    private func observeClock() {
        withObservationTracking {
            _ = progress.currentTime
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let published = self.published {
                    let expected = published.time + published.rate * Date().timeIntervalSince(published.at)
                    if abs(self.progress.currentTime - expected) > 1.5 { self.publish() }
                }
                self.observeClock()
            }
        }
    }

    // MARK: - Now playing info

    /// The current track's animated artwork, a video file on the device; `nil` removes it.
    public func setMotionVideo(_ video: URL?, for ref: PlayableRef) {
        guard let video else {
            if motion?.ref == ref { motion = nil; publish() }
            return
        }
        guard motion?.ref != ref || motion?.video != video else { return }
        Task {
            // Square (Apple Music's) or tall (Spotify Canvas, Apple's tall art): the lock screen has
            // a key for each, and gives each its own layout.
            let size = await Self.videoSize(video)
            guard nowPlaying.ref == ref else { return }
            motion = (ref, video, size.map { $0.width / max($0.height, 1) > 0.9 } ?? false)
            #if os(iOS)
            if #available(iOS 26.0, *) {
                PerfLog.info("NowPlaying: animated artwork for '\(ref.title)' (\(motion?.isSquare == true ? "1x1" : "3x4")); supported keys: \(MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys)")
            }
            #endif
            publish()
        }
    }

    private func publish() {
        guard let ref = nowPlaying.ref else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            published = nil
            return
        }

        let rate = transport.isPlaying && !transport.isBuffering ? 1.0 : 0.0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artist,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            // The length of the item that is actually playing, not the catalogue's claim about it:
            // the lock screen's scrubber is measuring this file. `0` is its "unknown length".
            MPMediaItemPropertyPlaybackDuration: nowPlaying.timelineDuration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.currentTime,
            // Zero while paused or buffering, so the lock screen's clock does not run ahead.
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let album = ref.album { info[MPMediaItemPropertyAlbumTitle] = album }

        loadArtwork(nowPlaying.artworkURL)
        if let artwork, artwork.url == nowPlaying.artworkURL {
            info[MPMediaItemPropertyArtwork] = artwork.value
        }

        #if os(iOS)
        if #available(iOS 26.0, *), let motion, motion.ref == ref {
            let key = motion.isSquare ? MPNowPlayingInfoProperty1x1AnimatedArtwork : MPNowPlayingInfoProperty3x4AnimatedArtwork
            if MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(key) {
                info[key] = Self.animatedArtwork(motion.video)
            }
        }
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = transport.isPlaying ? .playing : .paused
        published = (progress.currentTime, Date(), rate)

        // The lock screen greys out what will not work.
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = transport.canSkipForward
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = transport.canSkipBackward
    }

    /// Fetches and decodes the cover off the main actor, then publishes again with it.
    private func loadArtwork(_ url: URL?) {
        guard let url, artwork?.url != url, artworkTask == nil else { return }
        artworkTask = Task {
            defer { artworkTask = nil }
            guard let image = try? await KingfisherManager.shared.retrieveImage(with: ArtworkURL.best(from: url) ?? url).image,
                  nowPlaying.artworkURL == url
            else { return }
            self.artwork = (url, Self.artwork(image))
            publish()
        }
    }

    /// Built outside the main actor: MediaPlayer asks for the image on its own queue, and a
    /// closure formed on the main actor traps there.
    private nonisolated static func artwork(_ image: KFCrossPlatformImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private nonisolated static func videoSize(_ video: URL) async -> CGSize? {
        guard let track = try? await AVURLAsset(url: video).loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }
        let rotated = size.applying(transform)
        return CGSize(width: abs(rotated.width), height: abs(rotated.height))
    }

    #if os(iOS)
    /// The video as lock-screen artwork, its first frame standing in until it plays.
    @available(iOS 26.0, *)
    private nonisolated static func animatedArtwork(_ video: URL) -> MPMediaItemAnimatedArtwork {
        MPMediaItemAnimatedArtwork(
            artworkID: video.lastPathComponent,
            previewImageRequestHandler: { size, completion in
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = size
                generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
                    completion(image.map(UIImage.init(cgImage:)))
                }
            },
            videoAssetFileURLRequestHandler: { _, completion in completion(video) }
        )
    }
    #endif

    // MARK: - Remote commands

    /// Registers handlers for lock-screen, Control Centre, and headphone controls.
    ///
    /// Idempotent — registering twice would leave two handlers per command, so a single tap on the
    /// headphone button would skip two tracks.
    public func registerCommands() {
        guard !registered else { return }
        registered = true

        let center = MPRemoteCommandCenter.shared()

        // Play and pause do only what they say: a toggle here meant "pause" from a car while
        // already paused started the music.
        center.playCommand.addTarget { [commands, transport] _ in
            if !transport.isPlaying { commands.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [commands, transport] _ in
            if transport.isPlaying { commands.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [commands] _ in
            commands.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [commands] _ in
            commands.skipToNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [commands] _ in
            commands.skipToPrevious()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [commands] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            commands.seek(to: event.positionTime)
            return .success
        }

        for command in [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.nextTrackCommand, center.previousTrackCommand,
            center.changePlaybackPositionCommand,
        ] {
            command.isEnabled = true
        }

        // Explicitly off: cisum is a music player, and leaving these enabled makes some car head
        // units and headphones send seek events where a track skip was intended.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }
}
