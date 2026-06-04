import Models
import SwiftUI
import YouTubeSDK

// MARK: - Dummy Types for Default Values

final class DummyPlayerViewModel: PlayerViewModelInterface, @unchecked Sendable {
    nonisolated init() {}
    var currentTitle: String = ""
    var currentArtist: String = ""
    var currentImageURL: URL?
    var currentAccentColor: Color = .clear
    var isExplicit: Bool = false
    var currentVideoId: String?

    var isPlaying: Bool = false
    var duration: Double = 0
    var currentTime: Double = 0
    var canSkipForward: Bool = false
    var canSkipBackward: Bool = false

    var isLyricsVisible: Bool = false
    var lyricsState: LyricsState = .idle
    var syncedLyricsLines: [TimedLyricLine] = []
    var currentSyncedLyricIndex: Int?
    var plainLyricsText: String?

    func togglePlayPause() {}
    func skipToNext() {}
    func skipToPrevious() {}
    func seek(to _: Double) {}
    func load(song _: YouTubeMusicSong, preserveQueue _: Bool) {}
    func load(video _: YouTubeVideo, preserveQueue _: Bool) {}
    func load(external _: ExternalQueueTrack, preserveQueue _: Bool) {}
    func setQueue(_: [ExternalQueueTrack], startIndex _: Int) {}

    var artworkVideoStatus: ArtworkVideoProcessingStatus = .idle
    var animatedArtworkVideoURL: URL?
    var artworkVideoProgress: Double?
    var artworkVideoError: String?
    var lyricsAttribution: String?
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    @Entry var playerViewModel: any PlayerViewModelInterface = DummyPlayerViewModel()

    @Entry var searchViewModel: (any SearchViewModelInterface)?

    @Entry var youtube: YouTube?
}
