//
//  PlayerViewModel+UI.swift
//  Player
//
//  The 25 members Player/UI reads, backed by the new components.
//

import Foundation
import Models
import PlaybackCore
import SwiftUI

// This is a forwarding layer, not a second source of truth. Every property below reads through to
// NowPlayingState, TransportState, ProgressState, LyricsPresentation, or PlaybackQueue — nothing
// is stored here, so the two can never disagree.
//
// It exists so the player UI keeps working unchanged. There is no protocol and no dummy: views use
// `@Environment(PlayerViewModel.self)`, which needs neither. The old `DummyPlayerViewModel` existed
// only because a keypath-based environment value requires a non-optional default, and that default
// is exactly what silently swallowed every call when the environment wasn't wired.

public extension PlayerViewModel {
    // MARK: - Track

    var currentTitle: String {
        nowPlaying.title
    }

    var currentArtist: String {
        nowPlaying.artist
    }

    var currentImageURL: URL? {
        nowPlaying.artworkURL
    }

    var currentAccentColor: Color {
        nowPlaying.accentColor
    }

    var isExplicit: Bool {
        nowPlaying.isExplicit
    }

    /// The playing track's id on whichever source is serving it.
    ///
    /// Named for history — the UI uses it to gate actions that need something playing, and to key
    /// `.task(id:)` reloads. It is no longer necessarily a YouTube id; with the source registry it
    /// is whatever the active source calls the track, and is only meaningful alongside
    /// `nowPlaying.ref?.sourceID`.
    var currentVideoId: String? {
        nowPlaying.ref?.sourceTrackID
    }

    // MARK: - Transport

    var isPlaying: Bool {
        transport.isPlaying
    }

    var duration: Double {
        nowPlaying.duration
    }

    var canSkipForward: Bool {
        transport.canSkipForward
    }

    var canSkipBackward: Bool {
        transport.canSkipBackward
    }

    var playbackMode: PlaybackMode {
        transport.playbackMode
    }

    /// Playback position.
    ///
    /// - Note: This forwards to `ProgressState`, which updates ~30×/second. Any view reading it
    ///   through `PlayerViewModel` is invalidated at that rate along with every other view reading
    ///   *anything* on this object. Views that display a moving clock can read `ProgressState`
    ///   directly instead — `@Environment(ProgressState.self)` — and then only they redraw.
    var currentTime: Double {
        progress.currentTime
    }

    // MARK: - Lyrics

    var isLyricsVisible: Bool {
        get { lyrics.isVisible }
        set { lyrics.isVisible = newValue }
    }

    var lyricsState: LyricsState {
        lyrics.state
    }

    var syncedLyricsLines: [TimedLyricLine] {
        lyrics.syncedLines
    }

    var currentSyncedLyricIndex: Int? {
        lyrics.currentIndex
    }

    var plainLyricsText: String? {
        lyrics.plainText
    }

    var lyricsAttribution: String? {
        lyrics.attribution
    }

    // MARK: - Queue

    /// The whole queue, in play order, for the queue sheet.
    ///
    /// Indices line up with `currentQueuePreviewIndex` and `playQueueEntry(at:)`, which is what the
    /// UI relies on when it enumerates rows.
    var queuePreviewItems: [QueuePreviewItem] {
        queue.entries.map { ref in
            QueuePreviewItem(
                id: "\(ref.sourceID):\(ref.sourceTrackID)",
                title: ref.title,
                subtitle: ref.artist,
                artworkURL: ref.artworkURL
            )
        }
    }

    var currentQueuePreviewIndex: Int? {
        queue.position
    }

    /// The entry before the current one, for the background crossfade.
    var previousQueuePreviewItem: QueuePreviewItem? {
        guard let position = queue.position, position > 0 else { return nil }
        return queuePreviewItems[safe: position - 1]
    }

    /// The entry after the current one, for the background crossfade.
    var nextQueuePreviewItem: QueuePreviewItem? {
        guard let position = queue.position else { return nil }
        return queuePreviewItems[safe: position + 1]
    }

    func playQueueEntry(at index: Int) {
        queue.jump(to: index)
        guard let entry = queue.current else { return }
        load(entry, preserveQueue: true)
    }

    /// A row in the queue sheet.
    struct QueuePreviewItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let artworkURL: URL?

        public init(id: String, title: String, subtitle: String, artworkURL: URL?) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.artworkURL = artworkURL
        }
    }
}

private extension Array {
    /// Bounds-checked access. The queue can change between a view reading an index and using it,
    /// so the neighbour lookups above must not trap on a stale index.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
