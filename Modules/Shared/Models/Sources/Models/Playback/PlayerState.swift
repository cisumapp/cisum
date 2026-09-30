//
//  PlayerState.swift
//  Models
//
//  Player state, split by how often it changes rather than by what it is about.
//

import Foundation
import Observation
import SwiftUI

// The previous design was a single @MainActor @Observable protocol with 34 members covering track
// display, transport, lyrics, artwork-video processing, and queue mutation. Every view reading ANY
// member was invalidated when ANY member changed — and the members update at wildly different
// rates:
//
//     currentTime                  ~30 per second
//     currentSyncedLyricIndex      ~1 per second
//     isPlaying / canSkip*         on user action
//     title / artist / artwork     once per track
//
// So `currentTime` ticking 30x/second invalidated the mini player, the expanded player, the lyrics
// view, the queue list, and every artwork view at once. That is smell P1.1 in its most expensive
// form and was almost certainly the largest SwiftUI cost in the app.
//
// Splitting by FEATURE would not have fixed it: `currentTime` and `isPlaying` are both "transport",
// so they would have stayed together and the fan-out would have survived. Frequency is the axis
// that matters.
//
// MAINTENANCE RULE: a new member goes on the object matching its update frequency, or it gets a new
// one. If adding a member would force a 30 Hz object to be read by a view that only needs per-track
// data, the split is wrong — that is not a reason to merge them back.

/// What is playing. Changes once per track.
///
/// Read by the mini player, the expanded player, now-playing, and artwork views.
@MainActor
@Observable
public final class NowPlayingState {
    /// The playing track's identity, or `nil` when stopped.
    public var ref: PlayableRef?

    public var title: String = ""
    public var artist: String = ""
    public var artworkURL: URL?
    public var accentColor: Color = .gray
    public var isExplicit: Bool = false

    /// Total length in seconds. Lives here, not with progress: it changes once per track.
    public var duration: Double = 0

    public init() {}

    public var isEmpty: Bool {
        ref == nil
    }
}

/// Transport state. Changes on user action.
///
/// Read by the transport buttons.
@MainActor
@Observable
public final class TransportState {
    public var isPlaying: Bool = false
    public var canSkipForward: Bool = false
    public var canSkipBackward: Bool = false
    public var playbackMode: PlaybackMode = .off
    public var isBuffering: Bool = false

    public init() {}
}

/// Playback position. Changes roughly 30 times a second.
///
/// **Read by the scrubber and nothing else. That isolation is the entire point of this type** —
/// putting any other property here, or reading this one from a view that shows something else,
/// reintroduces exactly the fan-out the split exists to remove.
@MainActor
@Observable
public final class ProgressState {
    public var currentTime: Double = 0

    public init() {}
}

/// Lyrics presentation. Changes about once a second, and only while lyrics are visible.
///
/// Named `LyricsPresentation` rather than `LyricsState` because that name is already the enum
/// below, which this wraps.
@MainActor
@Observable
public final class LyricsPresentation {
    public var state: LyricsState = .idle
    public var syncedLines: [TimedLyricLine] = []
    public var currentIndex: Int?
    public var plainText: String?
    public var attribution: String?

    // Lyrics visibility is NOT tracked here. `PlayerViewModel.nowPlayingMode` owns it, because
    // showing lyrics, the queue, or artwork are three mutually-exclusive states of one stage —
    // a boolean here could disagree with the mode and there would be no right answer.

    public init() {}
}

/// Commands the UI can send to the player.
///
/// **Deliberately a protocol of methods with no observable state.** Transport buttons previously
/// observed the god object purely to call methods on it, so they re-rendered 30 times a second
/// while displaying nothing that had changed. A view holding one of these reads no state and is
/// never invalidated by playback progress.
@MainActor
public protocol PlaybackCommands: AnyObject, Sendable {
    func togglePlayPause()
    func skipToNext()
    func skipToPrevious()
    func seek(to timestamp: Double)
    func cyclePlaybackMode()

    /// Plays an already-identified track.
    ///
    /// Replaces the old `load(youtube:)` and `load(external:)` pair. The first was a
    /// YouTube-specific method on a supposedly generic interface — the same category error as a
    /// per-provider column on `Song`. The second took an `ExternalQueueTrack`, which carried a
    /// resolver closure instead of an identity.
    func load(_ ref: PlayableRef, preserveQueue: Bool)

    func setQueue(_ refs: [PlayableRef], startIndex: Int, shuffled: Bool)
}

/// Everything the player publishes, grouped for injection.
///
/// A view takes the one object it needs — `@Environment(ProgressState.self)` for the scrubber,
/// `@Environment(NowPlayingState.self)` for artwork — rather than the whole player. This type is a
/// convenience for wiring at the composition root, not something a view should observe wholesale.
@MainActor
public struct PlayerStates {
    public let nowPlaying: NowPlayingState
    public let transport: TransportState
    public let progress: ProgressState
    public let lyrics: LyricsPresentation
    public let commands: any PlaybackCommands

    public init(
        nowPlaying: NowPlayingState,
        transport: TransportState,
        progress: ProgressState,
        lyrics: LyricsPresentation,
        commands: any PlaybackCommands
    ) {
        self.nowPlaying = nowPlaying
        self.transport = transport
        self.progress = progress
        self.lyrics = lyrics
        self.commands = commands
    }
}
