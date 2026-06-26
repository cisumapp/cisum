import Foundation
import Models
import Observation
import SwiftUI

#if DEBUG
@MainActor
public final class MockPlayerViewModel: PlayerViewModelInterface {
    public var currentTitle: String = "Preview Song"
    public var currentArtist: String = "Preview Artist"
    public var currentImageURL: URL?
    public var currentAccentColor: Color = .pink
    public var isExplicit: Bool = false
    public var currentVideoId: String? = "123"

    public var isPlaying: Bool = true
    public var duration: Double = 200
    public var currentTime: Double = 50
    public var canSkipForward: Bool = true
    public var canSkipBackward: Bool = true

    public var isLyricsVisible: Bool = false
    public var lyricsState: LyricsState = .unavailable("Preview")
    public var syncedLyricsLines: [TimedLyricLine] = []
    public var currentSyncedLyricIndex: Int?
    public var plainLyricsText: String?

    public func togglePlayPause() {}
    public func skipToNext() {}
    public func skipToPrevious() {}
    public func seek(to _: Double) {}
    public func load(youtube _: YouTubeMediaRef, preserveQueue _: Bool) {}
    public func load(external _: ExternalQueueTrack, preserveQueue _: Bool) {}
    public func setQueue(_: [ExternalQueueTrack], startIndex _: Int) {}

    public var isCheckingHiResAvailability: Bool = false
    public var canSwitchToHiResVersion: Bool = false
    public var hiResAvailabilityMessage: String?
    public func checkForHiResVersion() async {}
    public func switchToHiResVersionIfAvailable() {}

    public var artworkVideoStatus: ArtworkVideoProcessingStatus = .idle
    public var animatedArtworkVideoURL: URL?
    public var artworkVideoProgress: Double?
    public var artworkVideoError: String?

    public var lyricsAttribution: String?

    public init() {}
}

#endif
