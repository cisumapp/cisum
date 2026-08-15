//
//  NowPlayingCenter.swift
//  Player
//
//  Lock screen, Control Centre, and hardware transport controls. One place.
//

import Foundation
import MediaPlayer
import Models
import Utilities

/// Publishes now-playing info and handles remote commands.
///
/// The previous implementation registered remote commands in the view model and built the
/// now-playing dictionary in a separate extension, so the two could and did drift — enabling a
/// command in one place while the other never populated the metadata it needed.
@MainActor
public final class NowPlayingCenter {
    private let commands: any PlaybackCommands
    private var registered = false

    public init(commands: any PlaybackCommands) {
        self.commands = commands
    }

    // MARK: - Now playing info

    /// Publishes what is playing.
    ///
    /// - Parameter artwork: Already decoded and sized. Decoding here would block the main actor at
    ///   exactly the moment the user is waiting for audio.
    public func update(
        nowPlaying: NowPlayingState,
        transport: TransportState,
        currentTime: Double,
        artwork: MPMediaItemArtwork? = nil
    ) {
        guard nowPlaying.ref != nil else {
            clear()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artist,
            MPMediaItemPropertyPlaybackDuration: nowPlaying.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            // Zero while paused, so the lock screen's clock does not keep advancing.
            MPNowPlayingInfoPropertyPlaybackRate: transport.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]

        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = transport.isPlaying ? .playing : .paused
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Remote commands

    /// Registers handlers for lock-screen, Control Centre, and headphone controls.
    ///
    /// Idempotent — registering twice would leave two handlers per command, so a single tap on the
    /// headphone button would skip two tracks.
    public func registerCommands() {
        guard !registered else { return }
        registered = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [commands] _ in
            commands.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [commands] _ in
            commands.togglePlayPause()
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

    /// Reflects whether skipping is currently possible, so the lock screen greys out what will not work.
    public func updateAvailability(canSkipForward: Bool, canSkipBackward: Bool) {
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = canSkipForward
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = canSkipBackward
    }
}
