//
//  PlayerViewModel.swift
//  cisum
//
//  Created by Aarav Gupta on 03/12/25.
//

public import Aesthetics
public import Combine
public import Models
import AVFoundation
import AVKit
import MediaPlayer
import ProviderSDK
import SwiftData
import SwiftUI
import Utilities

public typealias PlaybackCandidate = Caching.PlaybackCandidate

#if os(iOS)
import UIKit
#endif

public import YouTubeSDK

#if canImport(iTunesKit)
import iTunesKit
#endif

#if canImport(LyricsKit)
public import Caching
public import Radio
import LyricsKit
#endif

@Observable
@MainActor
public final class PlayerViewModel: PlayerViewModelInterface {
    public enum CachePolicy {
        public static let playbackURLTTL: TimeInterval = 60 * 2
        public static let playbackMinimumRemainingLifetime: TimeInterval = 60 * 3
        public static let preparedYouTubeMaxAge: TimeInterval = 300
        public static let highQualityArtworkTTL: TimeInterval = 60 * 60 * 24 * 14
        public static let motionArtworkSourceTTL: TimeInterval = 60 * 60 * 24
    }

    private enum Diagnostics {
        static let verbosePlaybackLogsEnabled = false
        static let verboseArtworkLogsEnabled = false
    }

    enum PlaybackRecoveryPolicy {
        static let maxAttemptsPerMediaID = 2
    }

    private enum RadioAutoplayPolicy {
        static let queueLowWatermark = 5
        static let maxSeedQueueTracks = 80
        static let minCachedTracksWithoutContinuation = 8
        static let minSeedTracksBeforePlaylistHydration = 16
    }

    /// Bitrate caps (bps) used to steer AVPlayer ABR hints for fast startup.
    static let bitRateCaps: [Int: Double] = [
        2160: 45_000_000,
        1440: 20_000_000,
        1080: 15_000_000,
        720: 8_000_000,
        480: 4_000_000,
        360: 1_500_000,
    ]

    public enum PlaybackQueueSource: String {
        case detached
        case searchMusic
        case searchVideo
        case searchExternal
        case radioAutoplay
        case userQueue
    }

    public enum StreamingService: String, Sendable {
        case youtube = "YouTube"
        case youtubeMusic = "YouTube Music"
        case spotify = "Spotify"
        case external = "External"
    }

    public struct TrackPresentationState: Sendable {
        public let mediaID: String
        public let title: String
        public let artist: String
        public let albumName: String?
        public let artworkURL: URL?
        public let isExplicit: Bool
        public let streamingService: StreamingService
        public let qualityLabel: String
        public let codecLabel: String
        public let durationHint: Int?
        public let queueIdentity: QueueIdentitySnapshot?

        public init(
            mediaID: String,
            title: String,
            artist: String,
            albumName: String?,
            artworkURL: URL?,
            isExplicit: Bool,
            streamingService: StreamingService,
            qualityLabel: String,
            codecLabel: String,
            durationHint: Int?,
            queueIdentity: QueueIdentitySnapshot?
        ) {
            self.mediaID = mediaID
            self.title = title
            self.artist = artist
            self.albumName = albumName
            self.artworkURL = artworkURL
            self.isExplicit = isExplicit
            self.streamingService = streamingService
            self.qualityLabel = qualityLabel
            self.codecLabel = codecLabel
            self.durationHint = durationHint
            self.queueIdentity = queueIdentity
        }
    }

    public struct PrioritizedCandidateResolution {
        public let candidates: [PlaybackCandidate]
        public let hiResPayload: ExternalStreamPayload?

        public init(candidates: [PlaybackCandidate], hiResPayload: ExternalStreamPayload?) {
            self.candidates = candidates
            self.hiResPayload = hiResPayload
        }
    }

    // MARK: - State

    public var player: AVPlayer {
        playbackEngine.player
    }

    let youtube: YouTube
    private let artworkVideoProcessor: ArtworkVideoProcessor
    private let tracker: WatchtimeTracker
    public var currentVideoId: String?
    public var playbackError: String?
    public var animatedArtworkVideoURL: URL?
    public var artworkVideoProgress: Double?
    public var artworkVideoStatus: ArtworkVideoProcessingStatus = .idle
    public var artworkVideoError: String?

    // Track Info
    public var currentTitle: String = "Not Playing"
    public var currentArtist: String = ""
    public var currentImageURL: URL?
    public var currentAccentColor: Color = .cisumAccent
    public var isExplicit: Bool = false
    public var currentStreamingServiceName: String = StreamingService.youtubeMusic.rawValue
    public var currentAudioQualityLabel: String = "Adaptive"
    public var currentAudioCodecLabel: String = "HLS"

    /// Number of times playback has stalled for the current item.
    private var stallCount = 0
    /// Timestamp set at the start of load() — used to log total video-start latency.
    private var videoLoadStartedAt: Date = .distantPast
    /// True from the moment replaceCurrentItem is called until readyToPlay fires.
    /// Used to suppress rate-observer false positives during item swaps.
    var isSwappingItem: Bool = false

    // MARK: - Controllers

    public let playbackEngine = PlaybackEngine()
    public let lyricsController = LyricsController()
    public let artworkController = ArtworkController()

    // MARK: - Delegated Properties

    public var isPlaying: Bool {
        playbackEngine.isPlaying
    }

    public var currentTime: Double {
        playbackEngine.currentTime
    }

    public var duration: Double {
        playbackEngine.duration
    }

    public var isLyricsVisible: Bool {
        get { lyricsController.isVisible }
        set { lyricsController.isVisible = newValue }
    }

    public var isQueueVisible: Bool = false

    public var lyricsState: LyricsState {
        lyricsController.state
    }

    public var syncedLyricsLines: [TimedLyricLine] {
        lyricsController.syncedLines
    }

    public var plainLyricsText: String? {
        lyricsController.plainText
    }

    public var lyricsAttribution: String? {
        lyricsController.attribution
    }

    // Queue
    public var queueSource: PlaybackQueueSource = .detached
    public var queuePosition: Int?
    public var queueCount: Int = 0
    public var canSkipForward: Bool {
        hasNextTrackInQueue
    }

    public var canSkipBackward: Bool {
        guard currentVideoId != nil else { return false }
        return hasPreviousTrackInQueue || currentTime > 5
    }

    public var queuePreviewItems: [QueuePreviewItem] = []

    private var timeObserver: Any?
    @ObservationIgnored var currentLoadTask: Task<Void, Never>?
    @ObservationIgnored var artworkLoadTask: Task<Void, Never>?
    @ObservationIgnored private var artworkVideoTask: Task<Void, Never>?

    private let queuePersistenceStore = QueuePersistenceStore()
    private var lastPersistedTime: TimeInterval = 0

    // MARK: - Telemetry

    public var pendingPlaybackTelemetryType: String?
    public var pendingPlaybackTelemetryStartedAt: Date?

    @ObservationIgnored var lyricsLoadTask: Task<Void, Never>?
    @ObservationIgnored var playbackRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var exhaustiveRetryTask: Task<Void, Never>?
    /// Tracks which mediaIDs have already had exhaustiveRetry attempted.
    /// Prevents the infinite loop: fail → retry → same URL → fail → retry...
    private var exhaustiveRetryAttemptedIDs: Set<String> = []
    var playbackRecoveryAttemptCounts: [String: Int] = [:]
    var playbackCandidates: [PlaybackCandidate] = []
    var playbackCandidateIndex: Int = 0
    var playbackCandidatesMediaID: String?
    var pendingPlaybackFormatOverride: (quality: String, codec: String)?
    private var currentAlbumNameHint: String?
    private var currentQueueIdentity: QueueIdentitySnapshot?
    var playbackQueue: [PlaybackQueueEntry] = [] {
        didSet {
            updateQueuePreviewItems()
        }
    }

    // Patch 3: Duplicate-load guard. Prevents multiple concurrent loads for the
    // same mediaID (e.g. rapid taps). Mirrors SmartTubeIOS's isLoading check.
    var isLoading: Bool = false
    var loadingMediaID: String?

    /// Patch 4: AsyncStream-based item status observer — replaces KVO.
    /// Cancelling itemObserverTask before replaceCurrentItem ensures stale
    /// callbacks from the previous item never fire against the new state.
    @ObservationIgnored private var itemObserverTask: Task<Void, Never>?

    // Patch 5: Async notification-based end observer — replaces NotificationCenter handle.
    @ObservationIgnored private var endObserverTask: Task<Void, Never>?
    @ObservationIgnored private var stallObserverTask: Task<Void, Never>?
    var webHLSProxyLoader: YTHLSProxyLoader? // Prevents ARC release during playback

    // Patch 7: Capture current playhead before a URL refresh so we can restore
    // the position once the new item reaches .readyToPlay.
    var savedPositionToRestore: TimeInterval?
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    let metadataCache: any VideoMetadataCaching
    #if canImport(iTunesKit)
    let itunes = iTunesKit()
    #endif
    let mediaCacheStore: MediaCacheStore
    let settings: PrefetchSettings
    let playbackMetricsStore: any PlaybackMetricsRecording
    private let scrobbleTrack: (TrackPresentationState, Date) async throws -> Void
    private let recordNowPlayingTrack: (TrackPresentationState) async throws -> Void
    private let isScrobblingEnabled: () -> Bool
    private let isLocalHistoryEnabled: () -> Bool
    private let startListeningSession: (TrackPresentationState) async -> PersistentIdentifier?
    private let finishListeningSession: (PersistentIdentifier, Date, Double, Bool, Date?) -> Void
    private let markScrobbledSession: (PersistentIdentifier, Date) -> Void
    let radioSessionStore: RadioSessionStore
    private var currentListeningSessionID: PersistentIdentifier?
    private var activeScrobbleSessionMediaID: String?
    private var hasSubmittedScrobbleForActiveSession = false
    @ObservationIgnored private var lastFMScrobbleTask: Task<Void, Never>?
    #if os(iOS)
    var artworkColorExtractor = ImageColorExtractor.shared
    #endif

    #if os(iOS)
    var nowPlayingState = NowPlayingState()
    var lastPublishedNowPlayingState: NowPlayingState?
    var currentArtworkResource: CachedNowPlayingArtworkResource?
    var currentArtworkMediaID: String?
    @ObservationIgnored var artworkCache: [String: CachedNowPlayingArtworkResource] = [:]
    @ObservationIgnored var cacheAccessOrder: [String: Date] = [:]
    @ObservationIgnored var artworkAccentCache: [String: (artworkURL: URL, color: Color)] = [:]
    @ObservationIgnored var artworkPaletteCache: [String: (artworkURL: URL, palette: ImageColorPalette?)] = [:]
    @ObservationIgnored var accentLoadTask: Task<Void, Never>?

    @ObservationIgnored var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored var routeChangeObserver: NSObjectProtocol?
    var wasPlayingBeforeInterruption = false
    #endif

    var hasNextTrackInQueue: Bool {
        guard let queuePosition else { return false }
        return queuePosition + 1 < playbackQueue.count
    }

    private var hasPreviousTrackInQueue: Bool {
        guard let queuePosition else { return false }
        return queuePosition > 0
    }

    var radioSeedVideoID: String?
    var radioPlaylistID: String?
    var radioContinuationToken: String?
    @ObservationIgnored var radioAutoplayTask: Task<Void, Never>?
    @ObservationIgnored var radioContinuationTask: Task<Void, Never>?
    var isLoadingRadioContinuation = false
    var preparedNextPlayback: PreparedQueuePlayback?
    @ObservationIgnored var nextPlaybackPreloadTask: Task<Void, Never>?
    @ObservationIgnored var timeBasedPrewarmTask: Task<Void, Never>?
    var preloadingNextMediaID: String?
    @ObservationIgnored var externalPayloadCache: [String: ExternalStreamPayload] = [:]
    @ObservationIgnored var distantPreloadCache: [String: PreparedQueuePlayback] = [:]
    @ObservationIgnored var distantPreloadTasks: [Task<Void, Never>] = []

    #if os(iOS)
    public init(
        youtube: YouTube,
        settings: PrefetchSettings,
        artworkVideoProcessor: ArtworkVideoProcessor,
        metadataCache: any VideoMetadataCaching,
        mediaCacheStore: MediaCacheStore,
        playbackMetricsStore: any PlaybackMetricsRecording,
        radioSessionStore: RadioSessionStore,
        scrobbleTrack: @escaping (TrackPresentationState, Date) async throws -> Void = { _, _ in },
        recordNowPlayingTrack: @escaping (TrackPresentationState) async throws -> Void = { _ in },
        isScrobblingEnabled: @escaping () -> Bool = { false },
        isLocalHistoryEnabled: @escaping () -> Bool = { false },
        startListeningSession: @escaping (TrackPresentationState) async -> PersistentIdentifier? = { _ in nil },
        finishListeningSession: @escaping (PersistentIdentifier, Date, Double, Bool, Date?) -> Void = { _, _, _, _, _ in },
        markScrobbledSession: @escaping (PersistentIdentifier, Date) -> Void = { _, _ in },
        artworkColorExtractor: ImageColorExtractor
    ) {
        self.youtube = youtube
        self.settings = settings
        self.artworkVideoProcessor = artworkVideoProcessor
        self.metadataCache = metadataCache
        self.mediaCacheStore = mediaCacheStore
        self.playbackMetricsStore = playbackMetricsStore
        self.radioSessionStore = radioSessionStore
        self.scrobbleTrack = scrobbleTrack
        self.recordNowPlayingTrack = recordNowPlayingTrack
        self.isScrobblingEnabled = isScrobblingEnabled
        self.isLocalHistoryEnabled = isLocalHistoryEnabled
        self.startListeningSession = startListeningSession
        self.finishListeningSession = finishListeningSession
        self.markScrobbledSession = markScrobbledSession
        self.artworkColorExtractor = artworkColorExtractor
        self.tracker = WatchtimeTracker(api: InnerTubeAPI())

        finishInitialization()
    }
    #else
    public init(
        youtube: YouTube,
        settings: PrefetchSettings,
        artworkVideoProcessor: ArtworkVideoProcessor,
        metadataCache: any VideoMetadataCaching,
        mediaCacheStore: MediaCacheStore,
        playbackMetricsStore: any PlaybackMetricsRecording,
        radioSessionStore: RadioSessionStore,
        scrobbleTrack: @escaping (TrackPresentationState, Date) async throws -> Void = { _, _ in },
        recordNowPlayingTrack: @escaping (TrackPresentationState) async throws -> Void = { _ in },
        isScrobblingEnabled: @escaping () -> Bool = { false },
        isLocalHistoryEnabled: @escaping () -> Bool = { false },
        startListeningSession: @escaping (TrackPresentationState) async -> PersistentIdentifier? = { _ in nil },
        finishListeningSession: @escaping (PersistentIdentifier, Date, Double, Bool, Date?) -> Void = { _, _, _, _, _ in },
        markScrobbledSession: @escaping (PersistentIdentifier, Date) -> Void = { _, _ in }
    ) {
        self.youtube = youtube
        self.settings = settings
        self.artworkVideoProcessor = artworkVideoProcessor
        self.metadataCache = metadataCache
        self.mediaCacheStore = mediaCacheStore
        self.playbackMetricsStore = playbackMetricsStore
        self.radioSessionStore = radioSessionStore
        self.scrobbleTrack = scrobbleTrack
        self.recordNowPlayingTrack = recordNowPlayingTrack
        self.isScrobblingEnabled = isScrobblingEnabled
        self.isLocalHistoryEnabled = isLocalHistoryEnabled
        self.startListeningSession = startListeningSession
        self.finishListeningSession = finishListeningSession
        self.markScrobbledSession = markScrobbledSession
        self.tracker = WatchtimeTracker(api: InnerTubeAPI())

        finishInitialization()
    }
    #endif

    private var rateObserverTask: Task<Void, Never>?

    private func finishInitialization() {
        configureAudioSession()
        configurePlayerForBackgroundPlayback()
        setupRemoteCommands()

        playbackEngine.onProgressUpdate = { [weak self] in
            guard let self else { return }
            handleProgressUpdate()
        }

        setupAudioLifecycleObservers()

        #if os(iOS)
        setupVolumeButtonSkip()
        #endif

        Color.resetDynamicAccent()
        currentAccentColor = Color.dynamicAccent

        restoreLastSession()
    }

    private func handleProgressUpdate() {
        let previousCanSkipBackward = canSkipBackward

        if canSkipBackward != previousCanSkipBackward {
            updateRemoteCommandState()
        }
        maybeSubmitLastFMScrobble()
        updateNowPlayingPlaybackInfo(force: false)

        // Persist session periodically (every 5s)
        if abs(currentTime - lastPersistedTime) > 5.0 || lastPersistedTime == 0 {
            persistCurrentSession()
        }
    }

    // MARK: - Playback Session State

    func preparePlaybackSession(for state: TrackPresentationState, preserveQueue: Bool) {
        if !preserveQueue {
            clearQueueContext()
        }

        currentQueueIdentity = state.queueIdentity
        applyTrackPresentation(state)
        resetPlaybackRuntimeState(for: state.mediaID)
        startTrackAncillaryWork(for: state)
    }

    private func applyTrackPresentation(_ state: TrackPresentationState) {
        currentTitle = state.title
        currentArtist = state.artist
        currentAlbumNameHint = state.albumName
        currentImageURL = state.artworkURL
        isExplicit = state.isExplicit
        currentStreamingServiceName = state.streamingService.rawValue
        currentAudioQualityLabel = state.qualityLabel
        currentAudioCodecLabel = state.codecLabel
        pendingPlaybackFormatOverride = nil
        currentVideoId = state.mediaID

        persistCurrentSession()
    }

    func makeQueueIdentitySnapshot(
        mediaID: String,
        title: String,
        artist: String,
        activeRepresentationKey: String?,
        hydrationState: [String],
        candidateSnapshot: [QueueCandidateSnapshot]
    ) -> QueueIdentitySnapshot {
        let fingerprint = "\(title.lowercased())|\(artist.lowercased())|\(mediaID.lowercased())"
        return QueueIdentitySnapshot(
            canonicalID: canonicalQueueID(for: fingerprint, fallback: mediaID),
            activeRepresentationKey: activeRepresentationKey,
            hydrationState: hydrationState,
            candidateSnapshot: candidateSnapshot
        )
    }

    private func resetPlaybackRuntimeState(for mediaID: String) {
        playbackError = nil
        stallCount = 0
        playbackEngine.resetProgress()
        resetPlaybackCandidates(for: mediaID)
        resetPlaybackRecoveryState(for: mediaID)
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        // Reset the retry guard so the new track gets one exhaustive retry attempt.
        // We intentionally keep IDs from *other* tracks so we don't re-enter for the previous track.
        exhaustiveRetryAttemptedIDs.remove(mediaID)
        resetArtworkVideoState()
        #if os(iOS)
        artworkLoadTask?.cancel()
        accentLoadTask?.cancel()
        applyCachedArtworkIfAvailable(for: mediaID)
        #endif
    }

    private func startTrackAncillaryWork(for state: TrackPresentationState) {
        startListeningSessionIfNeeded(for: state)
        startLyricsResolution(
            mediaID: state.mediaID,
            title: state.title,
            artist: state.artist,
            albumName: state.albumName,
            durationHint: state.durationHint
        )
        updateNowPlayingMetadata(force: true)
        #if os(iOS)
        loadNowPlayingArtwork(
            for: state.mediaID,
            title: state.title,
            artist: state.artist,
            fallbackURL: state.artworkURL
        )
        #endif
    }

    // MARK: - Loaders extracted to PlayerViewModel+Loading.swift

    // MARK: - Controls

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func skipToNext() {
        advanceToNextQueueEntry(triggeredByPlaybackEnd: false)
    }

    public func playQueueEntry(at index: Int) {
        guard playbackQueue.indices.contains(index) else { return }
        queuePosition = index
        stopCurrentPlaybackForImmediateTransition()
        load(entry: playbackQueue[index])
        preloadNextQueueEntryIfNeeded()
    }

    public func skipToPrevious() {
        guard currentVideoId != nil else {
            updateRemoteCommandState()
            return
        }

        if currentTime > 5 {
            seek(to: 0)
            return
        }

        guard hasPreviousTrackInQueue, let queuePosition else {
            seek(to: 0)
            return
        }

        let previousIndex = queuePosition - 1
        self.queuePosition = previousIndex
        stopCurrentPlaybackForImmediateTransition()
        load(entry: playbackQueue[previousIndex])
        preloadNextQueueEntryIfNeeded()
    }

    func advanceToNextQueueEntry(triggeredByPlaybackEnd: Bool) {
        guard hasNextTrackInQueue, let queuePosition else {
            playbackEngine.setIsPlaying(false)
            updateNowPlayingPlaybackInfo(force: true)
            updateRemoteCommandState()
            return
        }

        let nextIndex = queuePosition + 1
        guard playbackQueue.indices.contains(nextIndex) else {
            updateRemoteCommandState()
            return
        }

        let nextEntry = playbackQueue[nextIndex]
        self.queuePosition = nextIndex

        pendingPlaybackTelemetryType = triggeredByPlaybackEnd ? "auto-queue-transition" : "skip-next"
        pendingPlaybackTelemetryStartedAt = Date()

        if let prepared = preparedNextPlayback, prepared.mediaID == nextEntry.mediaID {
            preparedNextPlayback = nil
            if shouldRefreshPreparedPlaybackBeforeUse(prepared) {
                if !triggeredByPlaybackEnd {
                    stopCurrentPlaybackForImmediateTransition()
                }
                load(entry: nextEntry)
            } else {
                playPreparedQueueEntry(prepared)
            }
        } else if let distant = consumeDistantPreload(for: nextEntry.mediaID) {
            if shouldRefreshPreparedPlaybackBeforeUse(distant) {
                if !triggeredByPlaybackEnd {
                    stopCurrentPlaybackForImmediateTransition()
                }
                load(entry: nextEntry)
            } else {
                CisumLog.queue.info("Using distant preloaded id=\(distant.mediaID, privacy: .public)")
                playPreparedQueueEntry(distant)
            }
        } else {
            if !triggeredByPlaybackEnd {
                stopCurrentPlaybackForImmediateTransition()
            }
        }

        scheduleRadioContinuationIfNeeded()
        timeBasedPrewarmTask?.cancel()
        timeBasedPrewarmTask = nil
        preloadNextQueueEntryIfNeeded()
    }

    private func stopCurrentPlaybackForImmediateTransition() {
        currentLoadTask?.cancel()
        // Patch 4 & 5: Cancel both async observers before replacing the item.
        itemObserverTask?.cancel()
        itemObserverTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        playbackEngine.setIsPlaying(false)
        playbackEngine.resetProgress()
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
    }

    public func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlayingPlaybackInfo(force: true)
            }
        }
    }

    /// Reload the current video with current playback configuration.
    public func reloadCurrentVideo() {
        guard let id = currentVideoId else { return }
        let targetMediaID = id
        resetPlaybackCandidates(for: id)
        currentLoadTask?.cancel()
        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }
            do {
                let providerID = currentStreamingServiceName == StreamingService.youtube.rawValue ? "youtube" : "youtubeMusic"
                let representation = TrackRepresentation(
                    providerID: providerID,
                    providerTrackID: id,
                    title: currentTitle,
                    artist: currentArtist
                )
                let candidates = try await resolvePlaybackCandidates(
                    forID: id,
                    title: currentTitle,
                    artist: currentArtist,
                    representations: [representation]
                )

                if Task.isCancelled { return }
                guard currentVideoId == targetMediaID else { return }

                configurePlaybackCandidates(for: id, candidates: candidates)
                playCurrentPlaybackCandidate()
                startArtworkVideoProcessingIfNeeded(
                    for: id,
                    title: currentTitle,
                    artist: currentArtist,
                    albumName: currentAlbumNameHint
                )
            } catch {
                if error is CancellationError { return }
                guard currentVideoId == targetMediaID else { return }
                playbackError = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    public func handleScenePhaseChange(_ phase: ScenePhase) {
        VolumeButtonSkipController.shared.handleScenePhaseChange(phase)
        guard isPlaying else { return }
        switch phase {
        case .active, .background:
            reactivateAudioSessionIfNeeded()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
    #endif

    func load(entry: PlaybackQueueEntry) {
        webHLSProxyLoader = nil
        switch entry {
        case let .song(song):
            load(song: song, preserveQueue: true)
        case let .video(video):
            load(video: video, preserveQueue: true)
        case let .cachedRadio(track):
            loadMusicTrack(
                mediaID: track.videoID,
                title: track.title,
                artist: track.artist,
                albumName: track.albumName,
                thumbnailURL: track.thumbnailURL,
                explicit: track.isExplicit,
                durationHint: nil,
                preserveQueue: true
            )
        case let .external(track):
            load(external: track, preserveQueue: true)
        }
    }

    func loadExternalTrack(_ track: ExternalQueueTrack, preserveQueue: Bool) {
        let normalizedMediaID = track.mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMediaID.isEmpty else {
            playbackError = "Invalid media identifier for external stream."
            return
        }

        let tapStartedAt = Date()

        let displayTitle = normalizedMusicDisplayTitle(track.title, artist: track.artist)
        let displayArtist = normalizedMusicDisplayArtist(track.artist, title: track.title)
        let initialPresentation = TrackPresentationState(
            mediaID: normalizedMediaID,
            title: displayTitle,
            artist: displayArtist,
            albumName: nil,
            artworkURL: track.artworkURL,
            isExplicit: track.isExplicit,
            streamingService: Self.streamingService(for: track.service),
            qualityLabel: track.qualityLabelHint ?? "Resolving...",
            codecLabel: track.codecLabelHint ?? "Resolving...",
            durationHint: nil,
            queueIdentity: makeQueueIdentitySnapshot(
                mediaID: normalizedMediaID,
                title: displayTitle,
                artist: displayArtist,
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        )

        currentLoadTask?.cancel()
        preparePlaybackSession(for: initialPresentation, preserveQueue: preserveQueue)

        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            // Race BOTH resolution paths in parallel — whichever succeeds first wins.
            // Check cache first (MainActor-isolated, must be before task group).
            if let cachedPayload = externalPayloadCache[normalizedMediaID] {
                if Task.isCancelled { return }
                guard currentVideoId == normalizedMediaID else { return }

                currentTitle = normalizedMusicDisplayTitle(cachedPayload.title, artist: cachedPayload.artist)
                currentArtist = normalizedMusicDisplayArtist(cachedPayload.artist, title: cachedPayload.title)
                currentImageURL = cachedPayload.artworkURL ?? track.artworkURL
                currentStreamingServiceName = cachedPayload.service.rawValue
                currentAudioQualityLabel = cachedPayload.qualityLabel
                currentAudioCodecLabel = cachedPayload.codecLabel
                pendingPlaybackFormatOverride = (cachedPayload.qualityLabel, cachedPayload.codecLabel)

                let candidate = PlaybackCandidate(
                    url: cachedPayload.streamURL, streamKind: .audio,
                    mimeType: mimeTypeForCodecLabel(cachedPayload.codecLabel),
                    itag: nil, expiresAt: nil, isCompatible: true
                )
                configurePlaybackCandidates(for: normalizedMediaID, candidates: [candidate])
                playCurrentPlaybackCandidate()
                startArtworkVideoProcessingIfNeeded(for: normalizedMediaID, title: currentTitle, artist: currentArtist, albumName: nil)
                updateNowPlayingMetadata(force: true)
                if !preserveQueue { seedRadioQueueForExternalTrack(externalTrack: track, resolvedPayload: cachedPayload, expectedCurrentMediaID: normalizedMediaID) }
                preloadNextQueueEntryIfNeeded()
                #if os(iOS)
                loadNowPlayingArtwork(for: normalizedMediaID, title: currentTitle, artist: currentArtist, fallbackURL: currentImageURL)
                #endif
                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                    logPlayback("⏱️ COLD START TO PLAY (cache): \(elapsed) ms for \(normalizedMediaID)")
                }
                return
            }

            let result: Result<ExternalStreamPayload, Error>? = await withTaskGroup(of: Result<ExternalStreamPayload, Error>?.self, returning: Result<ExternalStreamPayload, Error>?.self) { group in
                // Path A: Primary resolvePayload (no MainActor access needed)
                group.addTask {
                    do {
                        let payload = try await track.resolvePayload()
                        return .success(payload)
                    } catch {
                        return .failure(error)
                    }
                }

                // Path B: YouTube fallback via PlaybackURLResolver (InnerTube WebSafari path)
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let candidates = try await resolvePlaybackCandidates(
                            forID: normalizedMediaID,
                            title: track.title,
                            artist: track.artist
                        )
                        // Wrap candidates in ExternalStreamPayload-compatible form
                        guard let bestCandidate = candidates.first else {
                            throw PlaybackURLResolver.ResolverError.resolutionFailed(mediaID: normalizedMediaID)
                        }
                        return .success(ExternalStreamPayload(
                            mediaID: normalizedMediaID,
                            streamURL: bestCandidate.url,
                            title: track.title,
                            artist: track.artist,
                            artworkURL: track.artworkURL,
                            service: track.service,
                            qualityLabel: track.qualityLabelHint ?? "YouTube",
                            codecLabel: track.codecLabelHint ?? "HLS"
                        ))
                    } catch {
                        return .failure(error)
                    }
                }

                // Collect first success, cancel remaining
                var lastError: Error?
                for await result in group {
                    if let result {
                        switch result {
                        case let .success(payload):
                            group.cancelAll()
                            return .success(payload)
                        case let .failure(error):
                            lastError = error
                        }
                    }
                }
                return lastError.map { .failure($0) }
            }

            guard let result else {
                if Task.isCancelled { return }
                handlePlaybackFailure(PlaybackURLResolver.ResolverError.resolutionFailed(mediaID: normalizedMediaID))
                return
            }

            switch result {
            case let .success(payload):
                if Task.isCancelled { return }
                guard currentVideoId == normalizedMediaID else { return }

                externalPayloadCache[normalizedMediaID] = payload
                currentTitle = normalizedMusicDisplayTitle(payload.title, artist: payload.artist)
                currentArtist = normalizedMusicDisplayArtist(payload.artist, title: payload.title)
                currentImageURL = payload.artworkURL ?? track.artworkURL
                currentStreamingServiceName = payload.service.rawValue
                currentAudioQualityLabel = payload.qualityLabel
                currentAudioCodecLabel = payload.codecLabel
                pendingPlaybackFormatOverride = (payload.qualityLabel, payload.codecLabel)

                let candidate = PlaybackCandidate(
                    url: payload.streamURL,
                    streamKind: .audio,
                    mimeType: mimeTypeForCodecLabel(payload.codecLabel),
                    itag: nil,
                    expiresAt: nil,
                    isCompatible: true
                )

                configurePlaybackCandidates(for: normalizedMediaID, candidates: [candidate])
                playCurrentPlaybackCandidate()
                startArtworkVideoProcessingIfNeeded(
                    for: normalizedMediaID,
                    title: currentTitle,
                    artist: currentArtist,
                    albumName: nil
                )
                updateNowPlayingMetadata(force: true)

                if !preserveQueue {
                    seedRadioQueueForExternalTrack(
                        externalTrack: track,
                        resolvedPayload: payload,
                        expectedCurrentMediaID: normalizedMediaID
                    )
                }

                preloadNextQueueEntryIfNeeded()

                #if os(iOS)
                loadNowPlayingArtwork(
                    for: normalizedMediaID,
                    title: currentTitle,
                    artist: currentArtist,
                    fallbackURL: currentImageURL
                )
                #endif

                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                    logPlayback("⏱️ COLD START TO PLAY: \(elapsed) ms for \(normalizedMediaID)")
                }

            case let .failure(error):
                if error is CancellationError { return }
                guard currentVideoId == normalizedMediaID else { return }
                handlePlaybackFailure(error)
            }
        }
    }

    private func clearQueueContext() {
        clearRadioAutoplayState()
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        playbackRecoveryAttemptCounts.removeAll(keepingCapacity: true)
        nextPlaybackPreloadTask?.cancel()
        nextPlaybackPreloadTask = nil
        timeBasedPrewarmTask?.cancel()
        timeBasedPrewarmTask = nil
        preparedNextPlayback = nil
        distantPreloadTasks.forEach { $0.cancel() }
        distantPreloadTasks.removeAll()
        distantPreloadCache.removeAll()
        externalPayloadCache.removeAll(keepingCapacity: true)
        playbackQueue = []
        queuePosition = nil
        queueCount = 0
        queueSource = .detached
        currentQueueIdentity = nil
        updateRemoteCommandState()
    }

    // MARK: - Queue Management extracted to PlayerViewModel+Queue.swift

    private func shouldRefreshPreparedPlaybackBeforeUse(_ prepared: PreparedQueuePlayback) -> Bool {
        guard prepared.streamingService == .youtube || prepared.streamingService == .youtubeMusic else {
            return false
        }

        if Date().timeIntervalSince(prepared.preparedAt) >= CachePolicy.preparedYouTubeMaxAge {
            return true
        }

        if prepared.playbackCandidates.contains(where: { $0.expiresAt == nil }) {
            return true
        }

        if let earliestExpiry = prepared.playbackCandidates.compactMap(\.expiresAt).min(),
           earliestExpiry.timeIntervalSinceNow <= CachePolicy.playbackMinimumRemainingLifetime
        {
            return true
        }

        return false
    }

    private func playPreparedQueueEntry(_ prepared: PreparedQueuePlayback) {
        currentLoadTask?.cancel()

        let presentation = TrackPresentationState(
            mediaID: prepared.mediaID,
            title: prepared.title,
            artist: prepared.artist,
            albumName: prepared.albumName,
            artworkURL: prepared.artworkURL,
            isExplicit: prepared.isExplicit,
            streamingService: prepared.streamingService,
            qualityLabel: prepared.qualityLabel,
            codecLabel: prepared.codecLabel,
            durationHint: prepared.durationHint,
            queueIdentity: prepared.queueIdentity
        )
        preparePlaybackSession(for: presentation, preserveQueue: true)

        if prepared.playbackCandidates.isEmpty {
            resetPlaybackCandidates(for: prepared.mediaID)
        } else {
            configurePlaybackCandidates(for: prepared.mediaID, candidates: prepared.playbackCandidates)
        }

        // Cancel stale observers before installing the preloaded item.
        itemObserverTask?.cancel()
        itemObserverTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil

        player.replaceCurrentItem(with: prepared.item)

        #if os(iOS)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        #endif

        playbackEngine.reactivateSession()
        observeItemStatus(prepared.item)
        observeItemEnd(prepared.item)
        observeItemStall(prepared.item)

        playbackEngine.resetProgress()
        playbackEngine.play()

        startArtworkVideoProcessingIfNeeded(
            for: prepared.mediaID,
            title: prepared.title,
            artist: prepared.artist,
            albumName: prepared.albumName
        )

        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
    }

    func playbackLabels(for candidate: PlaybackCandidate) -> (quality: String, codec: String) {
        let qualityLabel = switch candidate.streamKind {
        case .hls:
            "Adaptive"
        case .muxed:
            "Muxed"
        case .audio:
            "Direct Audio"
        }

        let codecLabel = codecLabel(for: candidate)
        return (qualityLabel, codecLabel)
    }

    private func codecLabel(for candidate: PlaybackCandidate) -> String {
        let mime = candidate.mimeType?.lowercased() ?? ""
        if mime.contains("flac") {
            return "FLAC"
        }
        if mime.contains("aac") || mime.contains("mp4a") || mime.contains("m4a") {
            return "AAC"
        }
        if mime.contains("mpeg") || mime.contains("mp3") {
            return "MP3"
        }
        if mime.contains("opus") {
            return "Opus"
        }
        if candidate.streamKind == .hls {
            return "HLS"
        }
        return "Unknown"
    }

    static func streamingService(for federatedService: FederatedService) -> StreamingService {
        switch federatedService {
        case .youtube:
            .youtube
        case .youtubeMusic:
            .youtubeMusic
        case .spotify:
            .spotify
        case .providerSDK:
            // ProviderSDK covers SoundCloud, Tidal, Qobuz, Deezer, etc.
            // These map to the existing .external streaming service type.
            .external
        }
    }

    // MARK: - Playback Resolution

    private func playFromBeginning(url: URL, headers: [String: String]? = nil) {
        logPlayback("Creating playback item url=\(url.absoluteString) host=\(url.host ?? "unknown") service=\(currentStreamingServiceName)")
        let item = makePlayerItem(for: url, headers: headers)

        // Fast Start Optimization: ask AVPlayer to buffer only 2 seconds before playing.
        item.preferredForwardBufferDuration = 2.0
        Task { [weak item] in
            try? await Task.sleep(for: .seconds(5))
            item?.preferredForwardBufferDuration = 0
        }

        // Apply ABR hint to load a lightweight segment first (e.g. 720p or 1080p equivalent audio/video).
        // Since cisum is primarily audio-focused, we cap it at a reasonable limit.
        if url.absoluteString.contains("m3u8") || url.absoluteString.contains("manifest") {
            item.preferredPeakBitRate = PlayerViewModel.bitRateCaps[720] ?? 8_000_000
        }

        // Patch 4 & 5: Cancel stale observers before replacing the item so a
        // previous item's .failed callback cannot fire against the new state.
        itemObserverTask?.cancel()
        itemObserverTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil

        player.replaceCurrentItem(with: item)

        #if os(iOS)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        #endif

        playbackEngine.reactivateSession()

        // Patch 4: Wire the AsyncStream-based status observer *after* replaceCurrentItem
        // so .readyToPlay is guaranteed to fire while the task is alive.
        observeItemStatus(item)
        // Patch 5: Wire the async end observer.
        observeItemEnd(item)
        observeItemStall(item)

        playbackEngine.resetProgress()
        playbackEngine.play()

        updateNowPlayingMetadata()
        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
        scheduleTimeBasedPrewarming()
    }

    private func resetPlaybackCandidates(for mediaID: String) {
        playbackCandidatesMediaID = mediaID
        playbackCandidates = []
        playbackCandidateIndex = 0
    }

    private func resetPlaybackRecoveryState(for mediaID: String) {
        playbackRecoveryAttemptCounts.removeValue(forKey: mediaID)
    }

    var supportsYouTubeCandidateRecovery: Bool {
        currentStreamingServiceName == StreamingService.youtube.rawValue
            || currentStreamingServiceName == StreamingService.youtubeMusic.rawValue
    }

    func playCurrentPlaybackCandidate() {
        guard playbackCandidateIndex < playbackCandidates.count else {
            if let fallback = playbackCandidates.first {
                logPlayback("Playback candidate index out of range, retrying first candidate for id=\(playbackCandidatesMediaID ?? "unknown")")
                updateAudioFormatLabels(for: fallback)
                playFromBeginning(url: fallback.url, headers: fallback.headers)
            }
            return
        }

        let candidate = playbackCandidates[playbackCandidateIndex]
        logPlayback(
            "Trying playback candidate #\(playbackCandidateIndex + 1) kind=\(candidate.streamKind.rawValue) for id=\(playbackCandidatesMediaID ?? "unknown")"
        )
        updateAudioFormatLabels(for: candidate)
        playFromBeginning(url: candidate.url, headers: candidate.headers)
    }

    // Removed exhaustiveRetry

    func canonicalPlaybackMediaID(_ mediaID: String) -> String {
        let trimmed = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("youtube-") {
            return String(trimmed.dropFirst("youtube-".count))
        }
        return trimmed
    }

    func startArtworkVideoProcessingIfNeeded(
        for mediaID: String,
        title: String,
        artist: String,
        albumName: String?
    ) {
        artworkVideoTask?.cancel()
        artworkVideoProgress = nil
        artworkVideoError = nil
        animatedArtworkVideoURL = nil

        let progressBridge = ArtworkVideoProgressBridge(viewModel: self, mediaID: mediaID)
        artworkVideoTask = Task { @MainActor [weak self, progressBridge] in
            guard let self else { return }
            logAnimatedArtwork("Processing started for id=\(mediaID)")

            do {
                guard let motionArtwork = await resolveMotionArtworkSource(
                    for: mediaID,
                    title: title,
                    artist: artist,
                    albumName: albumName
                ) else {
                    logAnimatedArtwork("No Animated Artwork found for id=\(mediaID)")
                    return
                }

                logAnimatedArtwork("Animated Artwork source found for id=\(mediaID): \(motionArtwork.sourceHLSURL.absoluteString)")

                guard !Task.isCancelled, currentVideoId == mediaID else { return }

                logAnimatedArtwork("Preparing motion artwork for id=\(mediaID)")
                artworkVideoStatus = .processing

                let localVideoURL = try await artworkVideoProcessor.prepareVideo(
                    for: mediaID,
                    cacheID: motionArtwork.videoCacheID,
                    sourceHLSURL: motionArtwork.sourceHLSURL,
                    progress: { progress in
                        progressBridge.report(progress)
                    }
                )

                guard !Task.isCancelled, currentVideoId == mediaID else { return }

                animatedArtworkVideoURL = localVideoURL
                artworkVideoProgress = 1
                artworkVideoStatus = .ready
                artworkVideoError = nil
                logAnimatedArtwork("Artwork found, transcoded, and loaded for id=\(mediaID): \(localVideoURL.lastPathComponent)")
                updateNowPlayingMetadata(force: true)
            } catch let error as ArtworkVideoProcessor.ArtworkVideoProcessorError {
                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }

                if case .cancelled = error {
                    self.logAnimatedArtwork("Processing cancelled for id=\(mediaID)")
                    return
                }

                self.animatedArtworkVideoURL = nil
                self.artworkVideoProgress = nil
                self.artworkVideoStatus = .failed
                self.artworkVideoError = error.localizedDescription
                self.logAnimatedArtwork("Artwork found but failed transcoding for id=\(mediaID): \(error.localizedDescription)")
                print("⚠️ PlayerViewModel: Artwork video processing failed: \(error.localizedDescription)")
            } catch {
                guard !Task.isCancelled, currentVideoId == mediaID else { return }

                animatedArtworkVideoURL = nil
                artworkVideoProgress = nil
                artworkVideoStatus = .failed
                artworkVideoError = error.localizedDescription
                logAnimatedArtwork("Artwork found but failed transcoding for id=\(mediaID): \(error.localizedDescription)")
                print("⚠️ PlayerViewModel: Artwork video processing failed: \(error.localizedDescription)")
            }
        }
    }

    func logAnimatedArtwork(_ message: String) {
        #if DEBUG
        guard Diagnostics.verboseArtworkLogsEnabled else { return }
        print("🖼️ PlayerViewModel: \(message)")
        #endif
    }

    func logPlayback(_ message: String) {
        #if DEBUG
        guard Diagnostics.verbosePlaybackLogsEnabled else { return }
        print("🎧 PlayerViewModel: \(message)")
        #endif
    }

    private func resetArtworkVideoState() {
        artworkVideoTask?.cancel()
        artworkVideoTask = nil
        animatedArtworkVideoURL = nil
        artworkVideoProgress = nil
        artworkVideoStatus = .idle
        artworkVideoError = nil
    }

    /// Patch 4: AsyncStream-based item status observer.
    /// The task is stored so it can be cancelled before replaceCurrentItem,
    /// eliminating the race window where a stale .failed fires against new state.
    private func observeItemStatus(_ item: AVPlayerItem) {
        itemObserverTask?.cancel()
        itemObserverTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            for await status in item.publisher(for: \.status).values where !Task.isCancelled {
                guard item === self.player.currentItem else { return }
                switch status {
                case .readyToPlay:
                    self.logPlayback("AVPlayerItem ready to play")

                    if let start = self.pendingPlaybackTelemetryStartedAt {
                        let elapsed = Date().timeIntervalSince(start) * 1000
                        let type = self.pendingPlaybackTelemetryType ?? "playback"
                        CisumLog.playback.notice("⏱️ TELEMETRY: \(type, privacy: .public) total latency (incl. buffer)=\(elapsed, format: .fixed(precision: 1), privacy: .public)ms id=\(self.currentVideoId ?? "unknown", privacy: .public)")
                        self.pendingPlaybackTelemetryStartedAt = nil
                        self.pendingPlaybackTelemetryType = nil
                    }

                    // Patch 7: Restore saved position after a URL refresh.
                    if let position = self.savedPositionToRestore {
                        self.savedPositionToRestore = nil
                        self.playbackEngine.seek(to: position)
                    }
                    if self.isPlaying {
                        self.player.play()
                    }
                    self.updateNowPlayingPlaybackInfo(force: true)
                    self.updateRemoteCommandState()

                case .failed:
                    let nsError = item.error as NSError?
                    let errorMessage = nsError?.localizedDescription ?? "unknown error"
                    let statusCode = Self.latestErrorStatusCode(for: item)
                    let errorCode = nsError?.code
                    let errorDomain = nsError?.domain
                    let failureReason = item.errorLog()?.events.last?.errorComment ?? item.errorLog()?.events.last?.serverAddress ?? "n/a"
                    let logSummary = item.errorLog()?.events.map { event in
                        "{domain=\(String(describing: event.errorDomain)) code=\(String(describing: event.errorStatusCode)) comment=\(String(describing: event.errorComment))}"
                    }.joined(separator: ", ") ?? "[]"
                    print("❌ PlayerViewModel: AVPlayerItem failed: message=\(errorMessage) domain=\(errorDomain ?? "n/a") code=\(errorCode.map(String.init) ?? "n/a") statusCode=\(statusCode.map(String.init) ?? "n/a") reason=\(failureReason)")
                    print("❌ PlayerViewModel: AVPlayerItem errorLog=\(logSummary)")

                    // Step 1: Try next local candidate (HLS → muxed → audio)
                    if self.attemptNextPlaybackCandidateIfAvailable(errorMessage: errorMessage) {
                        return
                    }

                    // Step 2: One-shot exhaustive retry — fetch fresh URLs from the network.
                    // Patch 6: No fullReset() — reuse the existing AVPlayer instance.
                    if let mediaID = self.playbackCandidatesMediaID,
                       !self.exhaustiveRetryAttemptedIDs.contains(mediaID)
                    {
                        self.exhaustiveRetryAttemptedIDs.insert(mediaID)
                        // Patch 7: Capture position before we swap the URL.
                        self.savedPositionToRestore = self.currentTime > 1 ? self.currentTime : nil
                        self.exhaustiveRetryTask?.cancel()
                        self.exhaustiveRetryTask = Task { @MainActor [weak self] in
                            guard let self else { return }
                            do {
                                let freshCandidates = try await self.resolvePlaybackCandidates(
                                    forID: mediaID,
                                    title: self.currentTitle,
                                    artist: self.currentArtist,
                                    forceDecipher: true
                                )
                                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }
                                if !freshCandidates.isEmpty {
                                    self.configurePlaybackCandidates(for: mediaID, candidates: freshCandidates)
                                    self.playCurrentPlaybackCandidate()
                                }
                            } catch {
                                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }
                                self.savedPositionToRestore = nil
                                self.playbackEngine.setIsPlaying(false)
                                self.playbackError = error.localizedDescription
                            }
                        }
                        return
                    }

                    // Step 3: Exhaustive retry already attempted — fall through.
                    if self.handlePlaybackPermissionFailureIfNeeded(
                        errorMessage: errorMessage,
                        statusCode: statusCode,
                        errorDomain: errorDomain,
                        errorCode: errorCode
                    ) {
                        return
                    }

                    if self.advanceQueueAfterUnrecoverableFailure(errorMessage: errorMessage) {
                        return
                    }

                    self.playbackEngine.setIsPlaying(false)
                    self.playbackError = item.error?.localizedDescription ?? "Failed to load media"
                    self.updateNowPlayingPlaybackInfo(force: true)
                    self.updateRemoteCommandState()

                case .unknown:
                    self.logPlayback("AVPlayerItem status unknown")

                @unknown default:
                    break
                }
            }
        }
    }

    private static func latestErrorStatusCode(for item: AVPlayerItem) -> Int? {
        guard let events = item.errorLog()?.events else {
            return nil
        }
        for event in events.reversed() {
            let statusCode = Int(event.errorStatusCode)
            if statusCode != 0 { return statusCode }
        }
        return nil
    }

    /// Patch 5: Async notification-based end observer.
    /// Stored as a Task so it is automatically cancelled before each replaceCurrentItem.
    private func observeItemEnd(_ item: AVPlayerItem) {
        endObserverTask?.cancel()
        endObserverTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let notifications = NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: item
            )
            for await _ in notifications where !Task.isCancelled {
                guard item === self.player.currentItem else { return }
                self.advanceToNextQueueEntry(triggeredByPlaybackEnd: true)
                return
            }
        }
    }

    /// Tracks playback stalls and emits telemetry events.
    private func observeItemStall(_ item: AVPlayerItem) {
        stallObserverTask?.cancel()
        stallObserverTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let notifications = NotificationCenter.default.notifications(
                named: .AVPlayerItemPlaybackStalled,
                object: item
            )
            for await _ in notifications where !Task.isCancelled {
                guard item === self.player.currentItem else { return }
                self.stallCount += 1
                CisumLog.playback.warning("⚠️ Playback stalled id=\(self.currentVideoId ?? "unknown", privacy: .public) stallCount=\(self.stallCount)")
                CisumSignpost.playback.event("playback-stall", "id=\(self.currentVideoId ?? "unknown") count=\(self.stallCount)")

                await self.playbackMetricsStore.recordStall()
            }
        }
    }

    // MARK: - Listening / Scrobbling Helpers

    private func startListeningSessionIfNeeded(for state: TrackPresentationState) {
        guard activeScrobbleSessionMediaID != state.mediaID else { return }

        finalizeCurrentListeningSession()
        activeScrobbleSessionMediaID = state.mediaID
        hasSubmittedScrobbleForActiveSession = false

        if isLocalHistoryEnabled() {
            Task {
                currentListeningSessionID = await startListeningSession(state)
            }
        }

        publishLastFMNowPlaying(for: state)
    }

    private func finalizeCurrentListeningSession() {
        lastFMScrobbleTask?.cancel()
        lastFMScrobbleTask = nil

        if isLocalHistoryEnabled(), let sessionID = currentListeningSessionID {
            finishListeningSession(sessionID, Date(), currentTime, hasSubmittedScrobbleForActiveSession, nil as Date?)
        }

        activeScrobbleSessionMediaID = nil
        hasSubmittedScrobbleForActiveSession = false
        currentListeningSessionID = nil
    }

    private func publishLastFMNowPlaying(for state: TrackPresentationState) {
        guard isScrobblingEnabled() else { return }
        Task {
            try? await recordNowPlayingTrack(state)
        }
    }

    private func maybeSubmitLastFMScrobble() {
        guard !hasSubmittedScrobbleForActiveSession,
              isScrobblingEnabled(),
              let mediaID = activeScrobbleSessionMediaID,
              mediaID == currentVideoId,
              isPlaying else { return }

        let threshold = scrobbleThreshold(for: duration)
        guard threshold > 0, currentTime >= threshold else { return }

        hasSubmittedScrobbleForActiveSession = true
        let stateForScrobble = TrackPresentationState(
            mediaID: mediaID,
            title: currentTitle,
            artist: currentArtist,
            albumName: currentAlbumNameHint,
            artworkURL: currentImageURL,
            isExplicit: false,
            streamingService: .youtube, // Dummy for scrobble
            qualityLabel: "",
            codecLabel: "",
            durationHint: duration.isFinite && duration > 0 ? Int(duration.rounded()) : nil,
            queueIdentity: nil
        )

        let playedAt = Date()
        lastFMScrobbleTask?.cancel()
        lastFMScrobbleTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await scrobbleTrack(stateForScrobble, playedAt)
                if isLocalHistoryEnabled(), let sessionID = currentListeningSessionID {
                    markScrobbledSession(sessionID, playedAt)
                }
            } catch {
                hasSubmittedScrobbleForActiveSession = false
            }
            lastFMScrobbleTask = nil
        }
    }

    private func scrobbleThreshold(for duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 240 }
        return min(duration / 2, 240)
    }

    // MARK: - Internal Setup

    private func setupRemoteCommands() {
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNext() }
            return .success
        }
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPrevious() }
            return .success
        }

        updateRemoteCommandState()
    }

    private func play() {
        guard !isPlaying else {
            updateRemoteCommandState()
            return
        }

        if player.currentItem == nil, currentVideoId != nil {
            reloadCurrentVideo()
            return
        }

        reactivateAudioSessionIfNeeded()
        playbackEngine.play()
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
    }

    private func pause() {
        guard isPlaying else {
            updateRemoteCommandState()
            return
        }

        playbackEngine.pause()
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
    }

    func updateRemoteCommandState() {
        remoteCommandCenter.playCommand.isEnabled = !isPlaying && currentVideoId != nil
        remoteCommandCenter.pauseCommand.isEnabled = isPlaying
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = currentVideoId != nil
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = currentVideoId != nil
        remoteCommandCenter.nextTrackCommand.isEnabled = canSkipForward
        remoteCommandCenter.previousTrackCommand.isEnabled = canSkipBackward
    }

    #if os(iOS)
    private func setupVolumeButtonSkip() {
        VolumeButtonSkipController.shared.configure()
        VolumeButtonSkipController.shared.onSkipForward = { [weak self] in
            self?.skipToNext()
        }
        VolumeButtonSkipController.shared.onSkipBackward = { [weak self] in
            self?.skipToPrevious()
        }
        VolumeButtonSkipController.shared.isPlaying = { [weak self] in
            self?.isPlaying ?? false
        }
        VolumeButtonSkipController.shared.canSkipForward = { [weak self] in
            self?.canSkipForward ?? false
        }
        VolumeButtonSkipController.shared.canSkipBackward = { [weak self] in
            self?.canSkipBackward ?? false
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
            }
            if let routeChangeObserver {
                NotificationCenter.default.removeObserver(routeChangeObserver)
            }
        }
    }
    #endif

    // MARK: - Persistence

    private func persistCurrentSession() {
        guard let mediaID = currentVideoId else { return }
        let state = PersistedTrackState(
            mediaID: mediaID,
            title: currentTitle,
            artist: currentArtist,
            albumName: currentAlbumNameHint,
            artworkURL: currentImageURL,
            isExplicit: isExplicit,
            playbackTime: currentTime
        )
        queuePersistenceStore.saveLastSession(state: state)
        lastPersistedTime = currentTime
    }

    public func restoreLastSession() {
        guard let state = queuePersistenceStore.loadLastSession() else { return }

        let restoredTrack = CachedRadioTrack(
            videoID: state.mediaID,
            title: state.title,
            artist: state.artist,
            albumName: state.albumName,
            thumbnailURL: state.artworkURL,
            isExplicit: state.isExplicit
        )

        playbackQueue = [.cachedRadio(restoredTrack)]
        queuePosition = 0
        queueCount = 1
        queueSource = .radioAutoplay

        let presentation = TrackPresentationState(
            mediaID: state.mediaID,
            title: state.title,
            artist: state.artist,
            albumName: state.albumName,
            artworkURL: state.artworkURL,
            isExplicit: state.isExplicit,
            streamingService: .youtubeMusic,
            qualityLabel: "Adaptive",
            codecLabel: "HLS",
            durationHint: nil,
            queueIdentity: restoredTrack.queueIdentity
        )

        applyTrackPresentation(presentation)

        savedPositionToRestore = state.playbackTime > 0 ? state.playbackTime : nil

        let seedSong = YouTubeMusicSong(
            id: state.mediaID,
            title: state.title,
            artists: [state.artist],
            album: state.albumName,
            duration: nil,
            thumbnailURL: state.artworkURL,
            videoId: state.mediaID,
            isExplicit: state.isExplicit
        )
        seedRadioQueue(from: seedSong)

        #if os(iOS)
        loadNowPlayingArtwork(
            for: state.mediaID,
            title: state.title,
            artist: state.artist,
            fallbackURL: state.artworkURL
        )
        updateNowPlayingPlaybackInfo(force: true)
        #endif
    }
}

private final class WeakPlayerViewModelBox: @unchecked Sendable {
    weak var value: PlayerViewModel?

    init(_ value: PlayerViewModel) {
        self.value = value
    }
}

private final class ArtworkVideoProgressBridge: @unchecked Sendable {
    private let viewModelBox: WeakPlayerViewModelBox
    private let mediaID: String

    init(viewModel: PlayerViewModel, mediaID: String) {
        self.viewModelBox = WeakPlayerViewModelBox(viewModel)
        self.mediaID = mediaID
    }

    nonisolated func report(_ progress: Double) {
        let viewModelBox = viewModelBox
        let mediaID = mediaID

        Task { @MainActor in
            guard let viewModel = viewModelBox.value,
                  viewModel.currentVideoId == mediaID else { return }
            viewModel.artworkVideoProgress = progress
            viewModel.artworkVideoStatus = .processing
        }
    }
}
