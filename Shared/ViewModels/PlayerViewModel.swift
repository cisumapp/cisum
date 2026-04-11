//
//  PlayerViewModel.swift
//  cisum
//
//  Created by Aarav Gupta on 03/12/25.
//

import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import YouTubeSDK
import iTunesKit

#if canImport(TidalKit)
import TidalKit
#endif

#if canImport(LyricsKit)
import LyricsKit
#endif

#if os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class PlayerViewModel {

    enum CachePolicy {
        static let playbackURLTTL: TimeInterval = 60 * 2
        static let playbackMinimumRemainingLifetime: TimeInterval = 60 * 3
        static let preparedYouTubeMaxAge: TimeInterval = 75
        static let highQualityArtworkTTL: TimeInterval = 60 * 60 * 24 * 14
        static let motionArtworkSourceTTL: TimeInterval = 60 * 60 * 24
    }

    private enum Diagnostics {
        static let verbosePlaybackLogsEnabled = false
        static let verboseArtworkLogsEnabled = false
    }

    private enum PlaybackRecoveryPolicy {
        static let maxAttemptsPerMediaID = 2
    }

    private enum RadioAutoplayPolicy {
        static let queueLowWatermark = 5
        static let maxSeedQueueTracks = 80
        static let minCachedTracksWithoutContinuation = 8
        static let minSeedTracksBeforePlaylistHydration = 16
    }

    enum ArtworkVideoProcessingStatus: Equatable {
        case idle
        case processing
        case ready
        case failed
    }

    enum PlaybackQueueSource: String {
        case detached
        case searchMusic
        case searchVideo
        case searchExternal
        case radioAutoplay
    }

    enum StreamingService: String {
        case youtube = "YouTube"
        case youtubeMusic = "YouTube Music"
        case tidal = "Tidal"
        case spotify = "Spotify"
        case external = "External"
    }

    struct QueuePreviewItem: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let artworkURL: URL?
    }

    @Observable
    @MainActor
    final class PlaybackProgressState {
        var duration: Double = 0.0
        var currentTime: Double = 0.0
    }

    struct ExternalQueueTrack {
        let mediaID: String
        let title: String
        let artist: String
        let artworkURL: URL?
        let service: FederatedService
        let isExplicit: Bool
        let qualityLabelHint: String?
        let codecLabelHint: String?
        let resolvePayload: @MainActor () async throws -> ExternalStreamPayload
    }

    private struct TrackPresentationState {
        let mediaID: String
        let title: String
        let artist: String
        let albumName: String?
        let artworkURL: URL?
        let isExplicit: Bool
        let streamingService: StreamingService
        let qualityLabel: String
        let codecLabel: String
        let durationHint: Int?
    }

    struct PrioritizedCandidateResolution {
        let candidates: [PlaybackCandidate]
        let hiResPayload: ExternalStreamPayload?
    }


    // MARK: - State
    var player: AVPlayer
    private let youtube: YouTube
    private let artworkVideoProcessor: ArtworkVideoProcessor
    var currentVideoId: String?
    var playbackError: String?
    var animatedArtworkVideoURL: URL?
    var artworkVideoProgress: Double?
    var artworkVideoStatus: ArtworkVideoProcessingStatus = .idle
    var artworkVideoError: String?

    // Track Info
    var currentTitle: String = "Not Playing"
    var currentArtist: String = ""
    var currentImageURL: URL?
    var currentAccentColor: Color = .cisumAccent
    var isExplicit: Bool = false
    var currentStreamingServiceName: String = StreamingService.youtubeMusic.rawValue
    var currentAudioQualityLabel: String = "Adaptive"
    var currentAudioCodecLabel: String = "HLS"
    var hiResAvailabilityMessage: String?
    var isCheckingHiResAvailability: Bool = false
    var canSwitchToHiResVersion: Bool {
        pendingHiResPayload != nil
    }
    var lyricsState: LyricsState = .idle
    var syncedLyricsLines: [TimedLyricLine] = []
    var plainLyricsText: String?
    var lyricsAttribution: String?
    var progressState = PlaybackProgressState()

    // Queue
    var queueSource: PlaybackQueueSource = .detached
    var queuePosition: Int?
    var queueCount: Int = 0
    var canSkipForward: Bool {
        hasNextTrackInQueue
    }
    var canSkipBackward: Bool {
        guard currentVideoId != nil else { return false }
        return hasPreviousTrackInQueue || currentTime > 5
    }

    var queuePreviewItems: [QueuePreviewItem] = []

    var currentQueuePreviewIndex: Int? {
        queuePosition
    }

    var previousQueuePreviewItem: QueuePreviewItem? {
        guard let queuePosition,
              queuePosition > 0,
              queuePreviewItems.indices.contains(queuePosition - 1) else {
            return nil
        }

        return queuePreviewItems[queuePosition - 1]
    }

    var nextQueuePreviewItem: QueuePreviewItem? {
        guard let queuePosition,
              queuePreviewItems.indices.contains(queuePosition + 1) else {
            return nil
        }

        return queuePreviewItems[queuePosition + 1]
    }

    var duration: Double {
        get { progressState.duration }
        set { progressState.duration = newValue }
    }

    var currentTime: Double {
        get { progressState.currentTime }
        set { progressState.currentTime = newValue }
    }

    var isPlaying = false {
        didSet {
#if os(iOS)
            guard oldValue != isPlaying else { return }
            VolumeButtonSkipController.shared.handlePlaybackStateChanged(isPlaying: isPlaying)
#endif
        }
    }

    // Private
    private var timeObserver: Any?
    private var currentLoadTask: Task<Void, Never>?
    var artworkLoadTask: Task<Void, Never>?
    private var artworkVideoTask: Task<Void, Never>?
    var lyricsLoadTask: Task<Void, Never>?
    private var playbackRecoveryTask: Task<Void, Never>?
    private var playbackRecoveryAttemptCounts: [String: Int] = [:]
    private var playbackCandidates: [PlaybackCandidate] = []
    private var playbackCandidateIndex: Int = 0
    private var playbackCandidatesMediaID: String?
    private var pendingPlaybackFormatOverride: (quality: String, codec: String)?
    private var currentAlbumNameHint: String?
    var playbackQueue: [PlaybackQueueEntry] = [] {
        didSet {
            queuePreviewItems = playbackQueue.map { makeQueuePreviewItem(from: $0) }
        }
    }
    private var currentItemStatusObservation: NSKeyValueObservation?
    private var currentItemEndObserver: NSObjectProtocol?
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private let metadataCache: any VideoMetadataCaching
    let itunes = iTunesKit()
    let mediaCacheStore: MediaCacheStore
    private let settings: PrefetchSettings
    private let playbackMetricsStore: any PlaybackMetricsRecording
    private let streamingProviderSettings: any StreamingProviderSettingsReading
    private let radioSessionStore: RadioSessionStore
#if os(iOS)
    let artworkColorExtractor: any ArtworkColorExtracting
#endif

#if os(iOS)
    var nowPlayingState = NowPlayingState()
    var lastPublishedNowPlayingState: NowPlayingState?
    var currentArtworkResource: CachedNowPlayingArtworkResource?
    var currentArtworkMediaID: String?
    var artworkCache: [String: CachedNowPlayingArtworkResource] = [:]
    var artworkAccentCache: [String: (artworkURL: URL, color: Color)] = [:]
    var accentLoadTask: Task<Void, Never>?

    var interruptionObserver: NSObjectProtocol?
    var routeChangeObserver: NSObjectProtocol?
    var wasPlayingBeforeInterruption = false
#endif

    private var hasNextTrackInQueue: Bool {
        guard let queuePosition else { return false }
        return queuePosition + 1 < playbackQueue.count
    }

    private var hasPreviousTrackInQueue: Bool {
        guard let queuePosition else { return false }
        return queuePosition > 0
    }

    private var radioSeedVideoID: String?
    private var radioPlaylistID: String?
    private var radioContinuationToken: String?
    private var radioAutoplayTask: Task<Void, Never>?
    private var radioContinuationTask: Task<Void, Never>?
    private var isLoadingRadioContinuation = false
    var preparedNextPlayback: PreparedQueuePlayback?
    var nextPlaybackPreloadTask: Task<Void, Never>?
    var preloadingNextMediaID: String?
    var externalPayloadCache: [String: ExternalStreamPayload] = [:]
    private var pendingHiResPayload: ExternalStreamPayload?

#if os(iOS)
    init(
        youtube: YouTube,
        settings: PrefetchSettings,
        artworkVideoProcessor: ArtworkVideoProcessor,
        metadataCache: any VideoMetadataCaching,
        mediaCacheStore: MediaCacheStore,
        playbackMetricsStore: any PlaybackMetricsRecording,
        streamingProviderSettings: any StreamingProviderSettingsReading,
        radioSessionStore: RadioSessionStore,
        artworkColorExtractor: any ArtworkColorExtracting
    ) {
        self.youtube = youtube
        self.settings = settings
        self.artworkVideoProcessor = artworkVideoProcessor
        self.metadataCache = metadataCache
        self.mediaCacheStore = mediaCacheStore
        self.playbackMetricsStore = playbackMetricsStore
        self.streamingProviderSettings = streamingProviderSettings
        self.radioSessionStore = radioSessionStore
        self.artworkColorExtractor = artworkColorExtractor
        self.player = AVPlayer()

        finishInitialization()
    }
#else
    init(
        youtube: YouTube,
        settings: PrefetchSettings,
        artworkVideoProcessor: ArtworkVideoProcessor,
        metadataCache: any VideoMetadataCaching,
        mediaCacheStore: MediaCacheStore,
        playbackMetricsStore: any PlaybackMetricsRecording,
        streamingProviderSettings: any StreamingProviderSettingsReading,
        radioSessionStore: RadioSessionStore
    ) {
        self.youtube = youtube
        self.settings = settings
        self.artworkVideoProcessor = artworkVideoProcessor
        self.metadataCache = metadataCache
        self.mediaCacheStore = mediaCacheStore
        self.playbackMetricsStore = playbackMetricsStore
        self.streamingProviderSettings = streamingProviderSettings
        self.radioSessionStore = radioSessionStore
        self.player = AVPlayer()

        finishInitialization()
    }
#endif

    private func finishInitialization() {
        configureAudioSession()
        configurePlayerForBackgroundPlayback()
        setupRemoteCommands()
        setupTimeObserver()
        setupAudioLifecycleObservers()

    #if os(iOS)
        VolumeButtonSkipController.shared.configure(playerViewModel: self, volumeController: .shared)
    #endif

        Color.resetDynamicAccent()
        currentAccentColor = Color.dynamicAccent
    }

    // MARK: - Playback Session State

    private func preparePlaybackSession(for state: TrackPresentationState, preserveQueue: Bool) {
        if !preserveQueue {
            clearQueueContext()
        }

        resetHiResAvailabilityState()
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
    }

    private func resetPlaybackRuntimeState(for mediaID: String) {
        playbackError = nil
        currentTime = 0
        duration = 0
        resetPlaybackCandidates(for: mediaID)
        resetPlaybackRecoveryState(for: mediaID)
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        resetArtworkVideoState()
#if os(iOS)
        artworkLoadTask?.cancel()
        accentLoadTask?.cancel()
        applyCachedArtworkIfAvailable(for: mediaID)
#endif
    }

    private func startTrackAncillaryWork(for state: TrackPresentationState) {
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

    // MARK: - Loaders

    func load(song: YouTubeMusicSong, in queue: [YouTubeMusicSong], source: PlaybackQueueSource = .searchMusic) {
        if source == .searchMusic {
            // Search picks should transition into radio-backed playback so manual skip follows radio recommendations.
            load(song: song, preserveQueue: false)
            return
        }

        let queueEntries = queue.map { PlaybackQueueEntry.song($0) }
        guard !queueEntries.isEmpty else {
            load(song: song)
            return
        }

        guard let selectedIndex = queueEntries.firstIndex(where: { $0.mediaID == song.videoId }) else {
            load(song: song)
            return
        }

        playbackQueue = queueEntries
        queuePosition = selectedIndex
        queueCount = queueEntries.count
        queueSource = source
        load(song: song, preserveQueue: true)
        preloadNextQueueEntryIfNeeded()
    }

    func load(video: YouTubeVideo, in queue: [YouTubeVideo], source: PlaybackQueueSource = .searchVideo) {
        if source == .searchVideo {
            load(video: video, preserveQueue: false)
            return
        }

        let queueEntries = queue.map { PlaybackQueueEntry.video($0) }
        guard !queueEntries.isEmpty else {
            load(video: video)
            return
        }

        guard let selectedIndex = queueEntries.firstIndex(where: { $0.mediaID == video.id }) else {
            load(video: video)
            return
        }

        playbackQueue = queueEntries
        queuePosition = selectedIndex
        queueCount = queueEntries.count
        queueSource = source
        load(video: video, preserveQueue: true)
        preloadNextQueueEntryIfNeeded()
    }

    func load(external track: ExternalQueueTrack, in queue: [ExternalQueueTrack], source: PlaybackQueueSource = .searchExternal) {
        if source == .searchExternal {
            load(external: track, preserveQueue: false)
            return
        }

        let queueEntries = queue.map { PlaybackQueueEntry.external($0) }
        guard !queueEntries.isEmpty else {
            load(external: track)
            return
        }

        guard let selectedIndex = queueEntries.firstIndex(where: { $0.mediaID == track.mediaID }) else {
            load(external: track)
            return
        }

        playbackQueue = queueEntries
        queuePosition = selectedIndex
        queueCount = queueEntries.count
        queueSource = source
        load(external: track, preserveQueue: true)
        preloadNextQueueEntryIfNeeded()
    }

    func load(external track: ExternalQueueTrack, preserveQueue: Bool = false) {
        loadExternalTrack(track, preserveQueue: preserveQueue)
    }

    func load(song: YouTubeMusicSong, preserveQueue: Bool = false) {
        loadMusicTrack(
            mediaID: song.videoId,
            title: song.title,
            artist: song.artistsDisplay,
            albumName: song.album,
            thumbnailURL: song.thumbnailURL,
            explicit: song.isExplicit,
            durationHint: Self.lyricsDurationHint(from: song.duration),
            preserveQueue: preserveQueue
        )

        if !preserveQueue {
            seedRadioQueue(from: song)
        }
    }

    func load(video: YouTubeVideo, preserveQueue: Bool = false) {
        let targetMediaID = video.id

        let tapStartedAt = Date()
        let fallbackURL = normalizedArtworkURL(from: video.thumbnailURL)
        let displayTitle = normalizedMusicDisplayTitle(video.title, artist: video.author)
        let displayArtist = normalizedMusicDisplayArtist(video.author, title: video.title)

        let presentation = TrackPresentationState(
            mediaID: targetMediaID,
            title: displayTitle,
            artist: displayArtist,
            albumName: nil,
            artworkURL: fallbackURL,
            isExplicit: false,
            streamingService: .youtube,
            qualityLabel: "Resolving...",
            codecLabel: "Resolving...",
            durationHint: Self.lyricsDurationHint(from: video.lengthInSeconds)
        )
        preparePlaybackSession(for: presentation, preserveQueue: preserveQueue)

        currentLoadTask?.cancel()
        currentLoadTask = Task {
            if Task.isCancelled { return }

            do {
                let candidates = try await self.resolvePlaybackCandidates(forID: video.id)

                if Task.isCancelled { return }
                guard self.currentVideoId == targetMediaID else { return }

                self.configurePlaybackCandidates(for: video.id, candidates: candidates)
                self.playCurrentPlaybackCandidate()
                self.startArtworkVideoProcessingIfNeeded(
                    for: video.id,
                    title: displayTitle,
                    artist: displayArtist,
                    albumName: nil
                )
                self.logPlayback("Started playback for video id=\(video.id)")

                if !preserveQueue {
                    self.seedRadioQueueForVideoTrack(
                        video: video,
                        expectedCurrentMediaID: targetMediaID
                    )
                }

                self.preloadNextQueueEntryIfNeeded()

                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await self.playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                }
            } catch {
                if error is CancellationError { return }
                guard self.currentVideoId == targetMediaID else { return }
                self.handlePlaybackFailure(error)
            }
        }
    }

    private func loadMusicTrack(
        mediaID: String,
        title: String,
        artist: String,
        albumName: String?,
        thumbnailURL: URL?,
        explicit: Bool,
        durationHint: Int?,
        preserveQueue: Bool
    ) {
        let targetMediaID = mediaID

        let tapStartedAt = Date()
        let displayTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let displayArtist = normalizedMusicDisplayArtist(artist, title: title)

        let presentation = TrackPresentationState(
            mediaID: mediaID,
            title: displayTitle,
            artist: displayArtist,
            albumName: albumName,
            artworkURL: thumbnailURL,
            isExplicit: explicit,
            streamingService: .youtubeMusic,
            qualityLabel: "Resolving...",
            codecLabel: "Resolving...",
            durationHint: durationHint
        )
        preparePlaybackSession(for: presentation, preserveQueue: preserveQueue)

        currentLoadTask?.cancel()
        currentLoadTask = Task {
            if Task.isCancelled { return }

            do {
                let prioritizedResolution = try await self.resolvePrioritizedPlaybackCandidates(
                    mediaID: mediaID,
                    title: displayTitle,
                    artist: displayArtist
                )

                if Task.isCancelled { return }
                guard self.currentVideoId == targetMediaID else { return }

                if let hiResPayload = prioritizedResolution.hiResPayload {
                    self.applyHiResPresentation(from: hiResPayload, fallbackArtworkURL: thumbnailURL)
                }

                self.configurePlaybackCandidates(for: mediaID, candidates: prioritizedResolution.candidates)
                self.playCurrentPlaybackCandidate()
                self.startArtworkVideoProcessingIfNeeded(
                    for: mediaID,
                    title: self.currentTitle,
                    artist: self.currentArtist,
                    albumName: albumName
                )

                if prioritizedResolution.hiResPayload != nil {
                    self.updateNowPlayingMetadata(force: true)
#if os(iOS)
                    self.loadNowPlayingArtwork(
                        for: mediaID,
                        title: self.currentTitle,
                        artist: self.currentArtist,
                        fallbackURL: self.currentImageURL
                    )
#endif
                    self.logPlayback("Started prioritized Hi-Res playback for song id=\(mediaID)")
                } else {
                    self.logPlayback("Started playback for song id=\(mediaID)")
                }

                self.preloadNextQueueEntryIfNeeded()

                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await self.playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                }
            } catch {
                if error is CancellationError { return }
                guard self.currentVideoId == targetMediaID else { return }
                self.handlePlaybackFailure(error)
            }
        }
    }

    func loadExternalStream(
        mediaID: String,
        streamURL: URL,
        title: String,
        artist: String,
        artworkURL: URL?,
        service: FederatedService,
        qualityLabel: String,
        codecLabel: String
    ) {
        let immediateTrack = ExternalQueueTrack(
            mediaID: mediaID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            service: service,
            isExplicit: false,
            qualityLabelHint: qualityLabel,
            codecLabelHint: codecLabel,
            resolvePayload: {
                ExternalStreamPayload(
                    mediaID: mediaID,
                    streamURL: streamURL,
                    title: title,
                    artist: artist,
                    artworkURL: artworkURL,
                    service: service,
                    qualityLabel: qualityLabel,
                    codecLabel: codecLabel
                )
            }
        )

        loadExternalTrack(immediateTrack, preserveQueue: false)
    }

    // MARK: - Controls

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func skipToNext() {
        advanceToNextQueueEntry(triggeredByPlaybackEnd: false)
    }

    func skipToPrevious() {
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

    private func advanceToNextQueueEntry(triggeredByPlaybackEnd: Bool) {
        guard hasNextTrackInQueue, let queuePosition else {
            isPlaying = false
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
        } else {
            if !triggeredByPlaybackEnd {
                stopCurrentPlaybackForImmediateTransition()
            }
            load(entry: nextEntry)
        }

        scheduleRadioContinuationIfNeeded()
        preloadNextQueueEntryIfNeeded()
    }

    private func stopCurrentPlaybackForImmediateTransition() {
        currentLoadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeCurrentItemEndObserver()
        isPlaying = false
        currentTime = 0
        duration = 0
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlayingPlaybackInfo(force: true)
            }
        }
    }

    /// Reload the current video with current playback configuration.
    func reloadCurrentVideo() {
        guard let id = currentVideoId else { return }
        let targetMediaID = id
        resetPlaybackCandidates(for: id)
        currentLoadTask?.cancel()
        currentLoadTask = Task {
            if Task.isCancelled { return }
            do {
                let candidates = try await self.resolvePlaybackCandidates(forID: id)

                if Task.isCancelled { return }
                guard self.currentVideoId == targetMediaID else { return }

                self.configurePlaybackCandidates(for: id, candidates: candidates)
                self.playCurrentPlaybackCandidate()
                self.startArtworkVideoProcessingIfNeeded(
                    for: id,
                    title: currentTitle,
                    artist: currentArtist,
                    albumName: currentAlbumNameHint
                )
            } catch {
                if error is CancellationError { return }
                guard self.currentVideoId == targetMediaID else { return }
                self.playbackError = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    func handleScenePhaseChange(_ phase: ScenePhase) {
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

    private func load(entry: PlaybackQueueEntry) {
        switch entry {
        case .song(let song):
            load(song: song, preserveQueue: true)
        case .video(let video):
            load(video: video, preserveQueue: true)
        case .cachedRadio(let track):
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
        case .external(let track):
            load(external: track, preserveQueue: true)
        }
    }

    private func loadExternalTrack(_ track: ExternalQueueTrack, preserveQueue: Bool) {
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
            durationHint: nil
        )

        currentLoadTask?.cancel()
        preparePlaybackSession(for: initialPresentation, preserveQueue: preserveQueue)

        currentLoadTask = Task {
            if Task.isCancelled { return }

            do {
                let payload: ExternalStreamPayload
                if let cachedPayload = self.externalPayloadCache[normalizedMediaID] {
                    payload = cachedPayload
                } else {
                    payload = try await track.resolvePayload()
                    self.externalPayloadCache[normalizedMediaID] = payload
                }

                if Task.isCancelled { return }
                guard self.currentVideoId == normalizedMediaID else { return }

                self.currentTitle = normalizedMusicDisplayTitle(payload.title, artist: payload.artist)
                self.currentArtist = normalizedMusicDisplayArtist(payload.artist, title: payload.title)
                self.currentImageURL = payload.artworkURL ?? track.artworkURL
                self.currentStreamingServiceName = payload.service.rawValue
                self.currentAudioQualityLabel = payload.qualityLabel
                self.currentAudioCodecLabel = payload.codecLabel
                self.pendingPlaybackFormatOverride = (payload.qualityLabel, payload.codecLabel)

                let candidate = PlaybackCandidate(
                    url: payload.streamURL,
                    streamKind: .audio,
                    mimeType: self.mimeTypeForCodecLabel(payload.codecLabel),
                    itag: nil,
                    expiresAt: nil,
                    isCompatible: true
                )

                self.configurePlaybackCandidates(for: normalizedMediaID, candidates: [candidate])
                self.playCurrentPlaybackCandidate()
                self.startArtworkVideoProcessingIfNeeded(
                    for: normalizedMediaID,
                    title: self.currentTitle,
                    artist: self.currentArtist,
                    albumName: nil
                )
                self.updateNowPlayingMetadata(force: true)

                if !preserveQueue {
                    self.seedRadioQueueForExternalTrack(
                        externalTrack: track,
                        resolvedPayload: payload,
                        expectedCurrentMediaID: normalizedMediaID
                    )
                }

                self.preloadNextQueueEntryIfNeeded()

#if os(iOS)
                self.loadNowPlayingArtwork(
                    for: normalizedMediaID,
                    title: self.currentTitle,
                    artist: self.currentArtist,
                    fallbackURL: self.currentImageURL
                )
#endif

                if self.settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await self.playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                }
            } catch {
                if error is CancellationError { return }
                guard self.currentVideoId == normalizedMediaID else { return }
                self.handlePlaybackFailure(error)
            }
        }
    }

    private func clearQueueContext() {
        clearRadioAutoplayState()
        resetHiResAvailabilityState()
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        playbackRecoveryAttemptCounts.removeAll(keepingCapacity: true)
        nextPlaybackPreloadTask?.cancel()
        nextPlaybackPreloadTask = nil
        preparedNextPlayback = nil
        externalPayloadCache.removeAll(keepingCapacity: true)
        playbackQueue = []
        queuePosition = nil
        queueCount = 0
        queueSource = .detached
        updateRemoteCommandState()
    }

    private func makeQueuePreviewItem(from entry: PlaybackQueueEntry) -> QueuePreviewItem {
        switch entry {
        case .song(let song):
            return QueuePreviewItem(
                id: song.videoId,
                title: normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay),
                subtitle: normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title),
                artworkURL: song.thumbnailURL
            )
        case .video(let video):
            return QueuePreviewItem(
                id: video.id,
                title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                subtitle: normalizedMusicDisplayArtist(video.author, title: video.title),
                artworkURL: normalizedArtworkURL(from: video.thumbnailURL)
            )
        case .cachedRadio(let track):
            return QueuePreviewItem(
                id: track.videoID,
                title: normalizedMusicDisplayTitle(track.title, artist: track.artist),
                subtitle: normalizedMusicDisplayArtist(track.artist, title: track.title),
                artworkURL: track.thumbnailURL
            )
        case .external(let track):
            return QueuePreviewItem(
                id: track.mediaID,
                title: normalizedMusicDisplayTitle(track.title, artist: track.artist),
                subtitle: normalizedMusicDisplayArtist(track.artist, title: track.title),
                artworkURL: track.artworkURL
            )
        }
    }

    private func seedRadioQueue(from seedSong: YouTubeMusicSong) {
        let seedVideoID = seedSong.videoId
        radioSeedVideoID = seedVideoID
        radioAutoplayTask?.cancel()

        radioAutoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let cachedSession = self.radioSessionStore.session(forSeedVideoID: seedVideoID)

            if let cachedSession,
               self.shouldReuseCachedRadioSession(cachedSession),
               self.currentVideoId == seedVideoID {
                self.applyCachedRadioSession(cachedSession, fallbackSeed: seedSong)
                self.scheduleRadioContinuationIfNeeded()
                return
            }

            do {
                let radio = try await self.youtube.music.getRadio(videoId: seedVideoID)
                guard !Task.isCancelled, self.currentVideoId == seedVideoID else { return }

                self.radioPlaylistID = radio.playlistId
                self.radioContinuationToken = radio.continuationToken

                var tracks = self.buildSeededRadioTracks(seedSong: seedSong, radioItems: radio.items)
                tracks = await self.hydrateSeedRadioTracksIfNeeded(tracks, playlistID: self.radioPlaylistID)
                guard !Task.isCancelled, self.currentVideoId == seedVideoID else { return }

                self.applyRadioTracksToQueue(tracks, seedVideoID: seedVideoID)
                self.scheduleRadioContinuationIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                if let cachedSession,
                   self.currentVideoId == seedVideoID,
                   !cachedSession.tracks.isEmpty {
                    self.applyCachedRadioSession(cachedSession, fallbackSeed: seedSong)
                    self.scheduleRadioContinuationIfNeeded()
                }
                self.logPlayback("Radio seed failed for id=\(seedVideoID): \(error.localizedDescription)")
            }
        }
    }

    private func seedRadioQueueForExternalTrack(
        externalTrack: ExternalQueueTrack,
        resolvedPayload: ExternalStreamPayload,
        expectedCurrentMediaID: String
    ) {
        guard resolvedPayload.service != .youtubeMusic else { return }

        let title = normalizedMusicDisplayTitle(resolvedPayload.title, artist: resolvedPayload.artist)
        let artist = normalizedMusicDisplayArtist(resolvedPayload.artist, title: resolvedPayload.title)
        let query = radioSeedQuery(title: title, artist: artist)
        guard !query.isEmpty else { return }

        radioAutoplayTask?.cancel()
        radioAutoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.currentVideoId == expectedCurrentMediaID else { return }

            do {
                let searchResults = try await self.youtube.music.search(query)
                guard !Task.isCancelled,
                      self.currentVideoId == expectedCurrentMediaID,
                      let seedSong = self.bestRadioSeedSong(
                        from: searchResults,
                        title: title,
                        artist: artist
                      ) else {
                    return
                }

                let seedVideoID = seedSong.videoId
                self.radioSeedVideoID = seedVideoID
                let leadingEntry = PlaybackQueueEntry.external(externalTrack)
                let cachedSession = self.radioSessionStore.session(forSeedVideoID: seedVideoID)

                if let cachedSession,
                   self.shouldReuseCachedRadioSession(cachedSession),
                   self.currentVideoId == expectedCurrentMediaID {
                    self.applyCachedRadioSession(
                        cachedSession,
                        fallbackSeed: seedSong,
                        leadingEntry: leadingEntry,
                        currentMediaID: expectedCurrentMediaID
                    )
                    self.scheduleRadioContinuationIfNeeded()
                    return
                }

                let radio = try await self.youtube.music.getRadio(videoId: seedVideoID)
                guard !Task.isCancelled, self.currentVideoId == expectedCurrentMediaID else { return }

                self.radioPlaylistID = radio.playlistId
                self.radioContinuationToken = radio.continuationToken

                var tracks = self.buildSeededRadioTracks(seedSong: seedSong, radioItems: radio.items)
                tracks = await self.hydrateSeedRadioTracksIfNeeded(tracks, playlistID: self.radioPlaylistID)
                guard !Task.isCancelled, self.currentVideoId == expectedCurrentMediaID else { return }

                self.applyRadioTracksToQueue(
                    tracks,
                    seedVideoID: seedVideoID,
                    leadingEntry: leadingEntry,
                    currentMediaID: expectedCurrentMediaID
                )
                self.scheduleRadioContinuationIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                self.logPlayback("External radio seed failed for query=\(query): \(error.localizedDescription)")
            }
        }
    }

    private func seedRadioQueueForVideoTrack(
        video: YouTubeVideo,
        expectedCurrentMediaID: String
    ) {
        let displayTitle = normalizedMusicDisplayTitle(video.title, artist: video.author)
        let displayArtist = normalizedMusicDisplayArtist(video.author, title: video.title)
        let query = radioSeedQuery(title: displayTitle, artist: displayArtist)
        let leadingEntry = PlaybackQueueEntry.video(video)

        radioAutoplayTask?.cancel()
        radioAutoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.currentVideoId == expectedCurrentMediaID else { return }

            do {
                let directRadio = try await self.youtube.music.getRadio(videoId: video.id)
                guard !Task.isCancelled,
                      self.currentVideoId == expectedCurrentMediaID else {
                    return
                }

                var directTracks = self.buildRadioTracks(from: directRadio.items)
                if !directTracks.isEmpty {
                    self.radioSeedVideoID = video.id
                    self.radioPlaylistID = directRadio.playlistId
                    self.radioContinuationToken = directRadio.continuationToken

                    directTracks = await self.hydrateSeedRadioTracksIfNeeded(
                        directTracks,
                        playlistID: self.radioPlaylistID
                    )
                    guard !Task.isCancelled,
                          self.currentVideoId == expectedCurrentMediaID else {
                        return
                    }

                    self.applyRadioTracksToQueue(
                        directTracks,
                        seedVideoID: video.id,
                        leadingEntry: leadingEntry,
                        currentMediaID: expectedCurrentMediaID
                    )
                    self.scheduleRadioContinuationIfNeeded()
                    return
                }
            } catch {
                self.logPlayback("Video direct radio seed failed for id=\(video.id): \(error.localizedDescription)")
            }

            guard !query.isEmpty else { return }

            do {
                let searchResults = try await self.youtube.music.search(query)
                guard !Task.isCancelled,
                      self.currentVideoId == expectedCurrentMediaID,
                      let seedSong = self.bestRadioSeedSong(
                        from: searchResults,
                        title: displayTitle,
                        artist: displayArtist
                      ) else {
                    return
                }

                let seedVideoID = seedSong.videoId
                self.radioSeedVideoID = seedVideoID
                let cachedSession = self.radioSessionStore.session(forSeedVideoID: seedVideoID)

                if let cachedSession,
                   self.shouldReuseCachedRadioSession(cachedSession),
                   self.currentVideoId == expectedCurrentMediaID {
                    self.applyCachedRadioSession(
                        cachedSession,
                        fallbackSeed: seedSong,
                        leadingEntry: leadingEntry,
                        currentMediaID: expectedCurrentMediaID
                    )
                    self.scheduleRadioContinuationIfNeeded()
                    return
                }

                let radio = try await self.youtube.music.getRadio(videoId: seedVideoID)
                guard !Task.isCancelled,
                      self.currentVideoId == expectedCurrentMediaID else {
                    return
                }

                self.radioPlaylistID = radio.playlistId
                self.radioContinuationToken = radio.continuationToken

                var tracks = self.buildSeededRadioTracks(seedSong: seedSong, radioItems: radio.items)
                tracks = await self.hydrateSeedRadioTracksIfNeeded(tracks, playlistID: self.radioPlaylistID)
                guard !Task.isCancelled,
                      self.currentVideoId == expectedCurrentMediaID else {
                    return
                }

                self.applyRadioTracksToQueue(
                    tracks,
                    seedVideoID: seedVideoID,
                    leadingEntry: leadingEntry,
                    currentMediaID: expectedCurrentMediaID
                )
                self.scheduleRadioContinuationIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                self.logPlayback("Video metadata radio seed failed for query=\(query): \(error.localizedDescription)")
            }
        }
    }

    private func radioSeedQuery(title: String, artist: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedTitle.isEmpty && !normalizedArtist.isEmpty {
            return "\(normalizedTitle) \(normalizedArtist)"
        }
        if !normalizedTitle.isEmpty {
            return normalizedTitle
        }
        return normalizedArtist
    }

    private func bestRadioSeedSong(from candidates: [YouTubeMusicSong], title: String, artist: String) -> YouTubeMusicSong? {
        guard !candidates.isEmpty else { return nil }

        let targetTitle = title.lowercased()
        let targetArtist = artist.lowercased()

        return candidates.max { lhs, rhs in
            let lhsTitle = normalizedMusicDisplayTitle(lhs.title, artist: lhs.artistsDisplay).lowercased()
            let rhsTitle = normalizedMusicDisplayTitle(rhs.title, artist: rhs.artistsDisplay).lowercased()
            let lhsArtist = normalizedMusicDisplayArtist(lhs.artistsDisplay, title: lhs.title).lowercased()
            let rhsArtist = normalizedMusicDisplayArtist(rhs.artistsDisplay, title: rhs.title).lowercased()

            let lhsScore = (0.7 * tokenOverlapScore(lhsTitle, targetTitle)) + (0.3 * tokenOverlapScore(lhsArtist, targetArtist))
            let rhsScore = (0.7 * tokenOverlapScore(rhsTitle, targetTitle)) + (0.3 * tokenOverlapScore(rhsArtist, targetArtist))
            return lhsScore < rhsScore
        }
    }

    private func shouldReuseCachedRadioSession(_ session: RadioSessionStore.Session) -> Bool {
        let validTrackCount = session.tracks.compactMap { CachedRadioTrack(cached: $0) }.count
        if validTrackCount == 0 {
            return false
        }
        return validTrackCount >= RadioAutoplayPolicy.minCachedTracksWithoutContinuation
    }

    private func hydrateSeedRadioTracksIfNeeded(
        _ tracks: [CachedRadioTrack],
        playlistID: String?
    ) async -> [CachedRadioTrack] {
        guard tracks.count < RadioAutoplayPolicy.minSeedTracksBeforePlaylistHydration else {
            return tracks
        }

        guard let playlistID = playlistID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !playlistID.isEmpty else {
            return tracks
        }

        do {
            let queueItems = try await youtube.music.getQueue(playlistId: playlistID)
            guard !queueItems.isEmpty else { return tracks }

            var merged = tracks
            var knownIDs = Set(merged.map(\.videoID))
            for song in queueItems {
                let track = CachedRadioTrack(song: song)
                guard knownIDs.insert(track.videoID).inserted else { continue }
                merged.append(track)
                if merged.count >= RadioAutoplayPolicy.maxSeedQueueTracks {
                    break
                }
            }

            if merged.count > tracks.count {
                logPlayback("Radio seed hydrated from playlist: +\(merged.count - tracks.count) track(s)")
            }

            return merged
        } catch {
            logPlayback("Radio seed hydration failed for playlistID=\(playlistID): \(error.localizedDescription)")
            return tracks
        }
    }

    private func clearRadioAutoplayState() {
        radioAutoplayTask?.cancel()
        radioAutoplayTask = nil
        radioContinuationTask?.cancel()
        radioContinuationTask = nil
        radioSeedVideoID = nil
        radioPlaylistID = nil
        radioContinuationToken = nil
        isLoadingRadioContinuation = false
    }

    private func applyCachedRadioSession(
        _ session: RadioSessionStore.Session,
        fallbackSeed: YouTubeMusicSong,
        leadingEntry: PlaybackQueueEntry? = nil,
        currentMediaID: String? = nil
    ) {
        var tracks = session.tracks.compactMap { CachedRadioTrack(cached: $0) }
        let seedTrack = CachedRadioTrack(song: fallbackSeed)

        if !tracks.contains(where: { $0.videoID == seedTrack.videoID }) {
            tracks.insert(seedTrack, at: 0)
        }

        radioPlaylistID = session.playlistID
        radioContinuationToken = session.continuationToken
        applyRadioTracksToQueue(
            Array(tracks.prefix(RadioAutoplayPolicy.maxSeedQueueTracks)),
            seedVideoID: seedTrack.videoID,
            leadingEntry: leadingEntry,
            currentMediaID: currentMediaID
        )
    }

    private func buildSeededRadioTracks(seedSong: YouTubeMusicSong, radioItems: [YouTubeMusicSong]) -> [CachedRadioTrack] {
        var tracks: [CachedRadioTrack] = []
        var seenIDs = Set<String>()

        let seedTrack = CachedRadioTrack(song: seedSong)
        if seenIDs.insert(seedTrack.videoID).inserted {
            tracks.append(seedTrack)
        }

        for item in radioItems {
            let track = CachedRadioTrack(song: item)
            guard seenIDs.insert(track.videoID).inserted else { continue }
            tracks.append(track)
            if tracks.count >= RadioAutoplayPolicy.maxSeedQueueTracks {
                break
            }
        }

        return tracks
    }

    private func buildRadioTracks(from radioItems: [YouTubeMusicSong]) -> [CachedRadioTrack] {
        var tracks: [CachedRadioTrack] = []
        var seenIDs = Set<String>()

        for item in radioItems {
            let track = CachedRadioTrack(song: item)
            guard seenIDs.insert(track.videoID).inserted else { continue }
            tracks.append(track)
            if tracks.count >= RadioAutoplayPolicy.maxSeedQueueTracks {
                break
            }
        }

        return tracks
    }

    private func applyRadioTracksToQueue(
        _ tracks: [CachedRadioTrack],
        seedVideoID: String,
        leadingEntry: PlaybackQueueEntry? = nil,
        currentMediaID: String? = nil
    ) {
        guard !tracks.isEmpty else { return }

        var entries = tracks.map { PlaybackQueueEntry.cachedRadio($0) }
        if let leadingEntry {
            entries.removeAll { $0.mediaID == leadingEntry.mediaID }
            entries.insert(leadingEntry, at: 0)
        }

        playbackQueue = entries
        queueCount = entries.count
        queueSource = .radioAutoplay

        let playbackMediaID = currentMediaID ?? currentVideoId
        if let playbackMediaID {
            queuePosition = entries.firstIndex(where: { $0.mediaID == playbackMediaID }) ?? 0
        } else {
            queuePosition = 0
        }

        if radioSeedVideoID == nil {
            radioSeedVideoID = seedVideoID
        }

        persistCurrentRadioSession()
        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
    }

    private func scheduleRadioContinuationIfNeeded() {
        guard queueSource == .radioAutoplay,
              let queuePosition,
              !isLoadingRadioContinuation,
              let continuation = radioContinuationToken,
              !continuation.isEmpty else {
            return
        }

        let remainingItems = playbackQueue.count - queuePosition - 1
        guard remainingItems <= RadioAutoplayPolicy.queueLowWatermark else {
            return
        }

        isLoadingRadioContinuation = true
        radioContinuationTask?.cancel()
        radioContinuationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isLoadingRadioContinuation = false
            }

            do {
                let previousToken = self.radioContinuationToken
                let page = try await self.youtube.music.getRadioContinuation(token: continuation)
                guard !Task.isCancelled,
                      self.queueSource == .radioAutoplay else {
                    return
                }

                self.radioContinuationToken = page.continuationToken
                if let playlistID = page.playlistId, !playlistID.isEmpty {
                    self.radioPlaylistID = playlistID
                }

                let appended = self.appendRadioTracks(page.items.map(CachedRadioTrack.init(song:)))
                if appended == 0 {
                    let tokenChanged = previousToken != self.radioContinuationToken
                    if !tokenChanged {
                        await self.backfillRadioTracksFromPlaylistIfNeeded()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await self.backfillRadioTracksFromPlaylistIfNeeded()
                self.logPlayback("Radio continuation failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func appendRadioTracks(_ incoming: [CachedRadioTrack]) -> Int {
        guard !incoming.isEmpty else { return 0 }

        var knownIDs = Set(playbackQueue.map(\.mediaID))
        var appended: [PlaybackQueueEntry] = []
        for track in incoming {
            guard knownIDs.insert(track.videoID).inserted else { continue }
            appended.append(.cachedRadio(track))
        }

        guard !appended.isEmpty else { return 0 }

        playbackQueue.append(contentsOf: appended)
        queueCount = playbackQueue.count
        persistCurrentRadioSession()
        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
        return appended.count
    }

    private func backfillRadioTracksFromPlaylistIfNeeded() async {
        guard queueSource == .radioAutoplay,
              let playlistID = radioPlaylistID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !playlistID.isEmpty else {
            return
        }

        do {
            let queueItems = try await youtube.music.getQueue(playlistId: playlistID)
            guard !queueItems.isEmpty else { return }

            let appended = appendRadioTracks(queueItems.map(CachedRadioTrack.init(song:)))
            if appended > 0 {
                logPlayback("Radio playlist backfill appended \(appended) track(s)")
            }
        } catch {
            logPlayback("Radio playlist backfill failed for playlistID=\(playlistID): \(error.localizedDescription)")
        }
    }

    private func persistCurrentRadioSession() {
        guard queueSource == .radioAutoplay,
              let seedVideoID = radioSeedVideoID else {
            return
        }

        let tracks = playbackQueue.compactMap { entry -> CachedRadioTrack? in
            switch entry {
            case .cachedRadio(let track):
                return track
            case .song(let song):
                return CachedRadioTrack(song: song)
            case .video:
                return nil
            case .external:
                return nil
            }
        }

        guard !tracks.isEmpty else { return }

        radioSessionStore.save(
            session: RadioSessionStore.Session(
                seedVideoID: seedVideoID,
                playlistID: radioPlaylistID,
                continuationToken: radioContinuationToken,
                tracks: tracks.map(\.persisted),
                updatedAt: .now
            )
        )
    }

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
           earliestExpiry.timeIntervalSinceNow <= CachePolicy.playbackMinimumRemainingLifetime {
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
            durationHint: prepared.durationHint
        )
        preparePlaybackSession(for: presentation, preserveQueue: true)

        if prepared.playbackCandidates.isEmpty {
            resetPlaybackCandidates(for: prepared.mediaID)
        } else {
            configurePlaybackCandidates(for: prepared.mediaID, candidates: prepared.playbackCandidates)
        }

        observeCurrentItemStatus(prepared.item)
        observeCurrentItemEnd(prepared.item)
        player.replaceCurrentItem(with: prepared.item)

#if os(iOS)
        if #available(iOS 14.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
#endif

        player.seek(to: .zero)
        isPlaying = true
        player.play()

        startArtworkVideoProcessingIfNeeded(
            for: prepared.mediaID,
            title: prepared.title,
            artist: prepared.artist,
            albumName: prepared.albumName
        )

        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
    }

    func checkForHiResVersion() async {
        guard !isCheckingHiResAvailability else {
            return
        }

        guard let currentMediaID = currentVideoId else {
            return
        }

        guard !currentMediaID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            return
        }

        let title = normalizedMusicDisplayTitle(currentTitle, artist: currentArtist)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = normalizedMusicDisplayArtist(currentArtist, title: currentTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "Not Playing" else {
            return
        }

        let lookupMediaID = currentMediaID
        isCheckingHiResAvailability = true
        pendingHiResPayload = nil
        hiResAvailabilityMessage = nil

        defer {
            isCheckingHiResAvailability = false
        }

#if canImport(TidalKit)
        do {
            let payload = try await resolveHiResTidalPayload(
                title: title,
                artist: artist,
                excludingMediaID: lookupMediaID
            )

            guard lookupMediaID == currentVideoId else { return }

            pendingHiResPayload = payload
            if payload != nil {
                hiResAvailabilityMessage = "Hi-Res available"
            }
        } catch is CancellationError {
            return
        } catch {
            guard lookupMediaID == currentVideoId else { return }
            playbackError = error.localizedDescription
        }
#else
        playbackError = "TidalKit is not linked to this target."
#endif
    }

    func switchToHiResVersionIfAvailable() {
        guard let payload = pendingHiResPayload else { return }

        loadExternalStream(
            mediaID: payload.mediaID,
            streamURL: payload.streamURL,
            title: payload.title,
            artist: payload.artist,
            artworkURL: payload.artworkURL,
            service: payload.service,
            qualityLabel: payload.qualityLabel,
            codecLabel: payload.codecLabel
        )

        pendingHiResPayload = nil
        hiResAvailabilityMessage = nil
    }

    private func resetHiResAvailabilityState() {
        pendingHiResPayload = nil
        hiResAvailabilityMessage = nil
        isCheckingHiResAvailability = false
    }

#if canImport(TidalKit)
    private struct HiResLookupCandidate {
        let id: Int
        let title: String
        let artistName: String
        let artworkURL: URL?
        let score: Double
    }

    private func resolveHiResTidalPayload(
        title: String,
        artist: String,
        excludingMediaID: String
    ) async throws -> ExternalStreamPayload? {
        let query = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }

        let normalizedTargetTitle = normalizedRankingText(title)
        let normalizedTargetArtist = normalizedRankingText(artist)
        let searchResults = try await Monochrome.shared.content.searchTracks(query: query)

        let candidates = searchResults
            .prefix(20)
            .compactMap { track -> HiResLookupCandidate? in
                let mediaID = "tidal-\(track.id)"
                if mediaID == excludingMediaID {
                    return nil
                }

                let normalizedCandidateTitle = normalizedRankingText(track.title)
                let normalizedCandidateArtist = normalizedRankingText(track.artist?.name ?? "")

                let titleScore = tokenOverlapScore(normalizedCandidateTitle, normalizedTargetTitle)
                guard titleScore >= 0.45 else {
                    return nil
                }

                let artistScore = tokenOverlapScore(normalizedCandidateArtist, normalizedTargetArtist)
                let exactTitleBoost = normalizedCandidateTitle == normalizedTargetTitle ? 0.18 : 0
                let score = (0.68 * titleScore) + (0.24 * artistScore) + exactTitleBoost

                return HiResLookupCandidate(
                    id: track.id,
                    title: track.title,
                    artistName: track.artist?.name ?? currentArtist,
                    artworkURL: tidalArtworkURL(from: track.album?.cover),
                    score: score
                )
            }
            .sorted { lhs, rhs in
                lhs.score > rhs.score
            }

        guard !candidates.isEmpty else {
            return nil
        }

        let preferredQuality = MonochromeAudioQuality(
            rawValue: streamingProviderSettings.tidalPreferredQualityRawValue
        ) ?? .hiResLossless
        let qualityOrder = hiResQualityFallbackOrder(preferred: preferredQuality)

        for candidate in candidates.prefix(3) {
            for quality in qualityOrder {
                guard let urlString = try? await Monochrome.shared.content.fetchStreamURL(
                    trackID: candidate.id,
                    quality: quality
                ),
                let streamURL = URL(string: urlString) else {
                    continue
                }

                return ExternalStreamPayload(
                    mediaID: "tidal-\(candidate.id)",
                    streamURL: streamURL,
                    title: candidate.title,
                    artist: candidate.artistName,
                    artworkURL: candidate.artworkURL,
                    service: .tidal,
                    qualityLabel: quality.label,
                    codecLabel: tidalCodecLabel(for: quality)
                )
            }
        }

        return nil
    }

    private func hiResQualityFallbackOrder(preferred: MonochromeAudioQuality) -> [MonochromeAudioQuality] {
        let allowedQualities: Set<MonochromeAudioQuality> = [.hiResLossless, .lossless, .high]
        let ordered = MonochromeAudioQuality.fallbackOrder(preferred: preferred)
        return ordered.filter { allowedQualities.contains($0) }
    }

    private func tidalCodecLabel(for quality: MonochromeAudioQuality) -> String {
        switch quality {
        case .lossless, .hiResLossless:
            return "FLAC"
        case .high, .medium, .low:
            return "AAC"
        }
    }
#endif

    func playbackLabels(for candidate: PlaybackCandidate) -> (quality: String, codec: String) {
        let qualityLabel: String
        switch candidate.streamKind {
        case .hls:
            qualityLabel = "Adaptive"
        case .muxed:
            qualityLabel = "Muxed"
        case .audio:
            qualityLabel = "Direct Audio"
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
            return .youtube
        case .youtubeMusic:
            return .youtubeMusic
        case .tidal:
            return .tidal
        case .spotify:
            return .spotify
        }
    }

    // MARK: - Playback Resolution

    private func resolvePlaybackEntry(forID id: String) async throws -> VideoMetadataCache.Entry {
        do {
            return try await metadataCache.resolve(id: id, metricsEnabled: settings.metricsEnabled) { key in
                try await self.youtube.main.video(id: key)
            }
        } catch {
            if error is CancellationError {
                throw error
            }

            print("⚠️ PlayerViewModel: First resolve failed for id=\(id): \(error.localizedDescription). Retrying once...")

            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 350_000_000)
            try Task.checkCancellation()

            return try await metadataCache.resolve(id: id, metricsEnabled: settings.metricsEnabled) { key in
                try await self.youtube.main.video(id: key)
            }
        }
    }

    func resolvePlaybackCandidates(forID id: String) async throws -> [PlaybackCandidate] {
        if let cachedCandidates = mediaCacheStore.playbackCandidates(
            for: id,
            maxAge: CachePolicy.playbackURLTTL
        ),
        !cachedCandidates.isEmpty {
            let hasUnknownExpiryCandidate = cachedCandidates.contains(where: { $0.expiresAt == nil })
            if hasUnknownExpiryCandidate {
                logPlayback("Cached playback candidates missing expiry for id=\(id); invalidating for refresh")
                mediaCacheStore.invalidatePlayback(for: id)
            } else if let earliestExpiry = cachedCandidates.compactMap(\.expiresAt).min(),
                      earliestExpiry.timeIntervalSinceNow <= CachePolicy.playbackMinimumRemainingLifetime {
                logPlayback("Cached playback candidates near expiry for id=\(id); invalidating for refresh")
                mediaCacheStore.invalidatePlayback(for: id)
            } else {
                logPlayback("Using cached playback candidates for id=\(id)")
                return cachedCandidates
            }
        }

        let entry = try await resolvePlaybackEntry(forID: id)
        let candidates = PlaybackCandidateBuilder.fromVideo(
            entry.video,
            preferredURL: entry.resolvedURL,
            validUntil: entry.validUntil
        )

        guard !candidates.isEmpty else {
            throw YouTubeError.decipheringFailed(videoId: id)
        }

        mediaCacheStore.savePlaybackResolution(
            mediaID: id,
            candidates: candidates,
            validUntil: entry.validUntil
        )

        return candidates
    }

    func resolvePrioritizedPlaybackCandidates(
        mediaID: String,
        title: String,
        artist: String
    ) async throws -> PrioritizedCandidateResolution {
#if canImport(TidalKit)
        async let youtubeCandidatesTask: [PlaybackCandidate] = try resolvePlaybackCandidates(forID: mediaID)

        let hiResPayload: ExternalStreamPayload?
        do {
            if let cachedPayload = externalPayloadCache[mediaID],
               cachedPayload.service == .tidal {
                hiResPayload = cachedPayload
            } else {
                hiResPayload = try await resolveHiResTidalPayload(
                    title: title,
                    artist: artist,
                    excludingMediaID: mediaID
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            hiResPayload = nil
        }

        if let hiResPayload {
            externalPayloadCache[mediaID] = hiResPayload

            let hiResCandidate = PlaybackCandidate(
                url: hiResPayload.streamURL,
                streamKind: .audio,
                mimeType: mimeTypeForCodecLabel(hiResPayload.codecLabel),
                itag: nil,
                expiresAt: nil,
                isCompatible: true
            )
            let youtubeFallbackCandidates = (try? await youtubeCandidatesTask) ?? []

            return PrioritizedCandidateResolution(
                candidates: [hiResCandidate] + youtubeFallbackCandidates,
                hiResPayload: hiResPayload
            )
        }

        let youtubeCandidates = try await youtubeCandidatesTask
        return PrioritizedCandidateResolution(candidates: youtubeCandidates, hiResPayload: nil)
#else
        let youtubeCandidates = try await resolvePlaybackCandidates(forID: mediaID)
        return PrioritizedCandidateResolution(candidates: youtubeCandidates, hiResPayload: nil)
#endif
    }

    private func applyHiResPresentation(from payload: ExternalStreamPayload, fallbackArtworkURL: URL?) {
        currentTitle = normalizedMusicDisplayTitle(payload.title, artist: payload.artist)
        currentArtist = normalizedMusicDisplayArtist(payload.artist, title: payload.title)
        currentImageURL = payload.artworkURL ?? fallbackArtworkURL
        currentStreamingServiceName = StreamingService.tidal.rawValue
        currentAudioQualityLabel = payload.qualityLabel
        currentAudioCodecLabel = payload.codecLabel
        pendingPlaybackFormatOverride = (payload.qualityLabel, payload.codecLabel)
    }

    private func playFromBeginning(url: URL) {
        let item = makePlayerItem(for: url)
        observeCurrentItemStatus(item)
        observeCurrentItemEnd(item)
        player.replaceCurrentItem(with: item)

        #if os(iOS)
        if #available(iOS 14.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        #endif

        seek(to: .zero)
        currentTime = 0
        duration = 0
        isPlaying = true
        player.play()

        updateNowPlayingMetadata()
        updateRemoteCommandState()
        preloadNextQueueEntryIfNeeded()
    }

    func makePlayerItem(for url: URL, service: StreamingService? = nil) -> AVPlayerItem {
        let resolvedService: StreamingService
        if let service {
            resolvedService = service
        } else {
            resolvedService = StreamingService(rawValue: currentStreamingServiceName) ?? .youtubeMusic
        }

        let isYouTubeSource = resolvedService == .youtube || resolvedService == .youtubeMusic

        let asset: AVURLAsset
        if isYouTubeSource,
           shouldInjectYouTubeHeaders(for: url) {
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                "Referer": "https://www.youtube.com/",
                "Origin": "https://www.youtube.com"
            ]

            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        } else {
            asset = AVURLAsset(url: url)
        }

        return AVPlayerItem(asset: asset)
    }

    private func shouldInjectYouTubeHeaders(for url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }

        if host.contains("googlevideo.com") || host.contains("googleusercontent.com") {
            return false
        }

        return host.contains("youtube.com")
            || host.contains("youtu.be")
            || host.contains("youtubei.googleapis.com")
    }

    func mimeTypeForCodecLabel(_ codecLabel: String) -> String? {
        let normalized = codecLabel.lowercased()
        if normalized.contains("flac") { return "audio/flac" }
        if normalized.contains("aac") { return "audio/aac" }
        if normalized.contains("mp3") { return "audio/mpeg" }
        if normalized.contains("hls") { return "application/x-mpegURL" }
        return nil
    }

    private func updateAudioFormatLabels(for candidate: PlaybackCandidate) {
        if let pendingPlaybackFormatOverride {
            currentAudioQualityLabel = pendingPlaybackFormatOverride.quality
            currentAudioCodecLabel = pendingPlaybackFormatOverride.codec
            self.pendingPlaybackFormatOverride = nil
            return
        }

        let labels = playbackLabels(for: candidate)
        currentAudioQualityLabel = labels.quality
        currentAudioCodecLabel = labels.codec
    }

    private func configurePlaybackCandidates(for mediaID: String, candidates: [PlaybackCandidate]) {
        playbackCandidatesMediaID = mediaID
        playbackCandidates = candidates
        playbackCandidateIndex = 0
        logPlayback("Prepared \(candidates.count) playback candidate(s) for id=\(mediaID)")
        let hostSummary = candidates
            .map { "\($0.streamKind.rawValue):\($0.url.host ?? "unknown-host")" }
            .joined(separator: " | ")
        logPlayback("Candidate hosts for id=\(mediaID): \(hostSummary)")
    }

    private func resetPlaybackCandidates(for mediaID: String) {
        playbackCandidatesMediaID = mediaID
        playbackCandidates = []
        playbackCandidateIndex = 0
    }

    private func resetPlaybackRecoveryState(for mediaID: String) {
        playbackRecoveryAttemptCounts.removeValue(forKey: mediaID)
    }

    private var supportsYouTubeCandidateRecovery: Bool {
        currentStreamingServiceName == StreamingService.youtube.rawValue
            || currentStreamingServiceName == StreamingService.youtubeMusic.rawValue
    }

    private func playCurrentPlaybackCandidate() {
        guard playbackCandidateIndex < playbackCandidates.count else {
            if let fallback = playbackCandidates.first {
                logPlayback("Playback candidate index out of range, retrying first candidate for id=\(playbackCandidatesMediaID ?? "unknown")")
                updateAudioFormatLabels(for: fallback)
                playFromBeginning(url: fallback.url)
            }
            return
        }

        let candidate = playbackCandidates[playbackCandidateIndex]
        logPlayback(
            "Trying playback candidate #\(playbackCandidateIndex + 1) kind=\(candidate.streamKind.rawValue) for id=\(playbackCandidatesMediaID ?? "unknown")"
        )
        updateAudioFormatLabels(for: candidate)
        playFromBeginning(url: candidate.url)
    }

    private func attemptNextPlaybackCandidateIfAvailable(errorMessage: String) -> Bool {
        guard let mediaID = currentVideoId,
              playbackCandidatesMediaID == mediaID,
              playbackCandidateIndex + 1 < playbackCandidates.count else {
            return false
        }

        playbackCandidateIndex += 1
        let candidate = playbackCandidates[playbackCandidateIndex]
        logPlayback(
            "Trying fallback playback candidate #\(playbackCandidateIndex + 1) kind=\(candidate.streamKind.rawValue) for id=\(mediaID) after error=\(errorMessage)"
        )
        updateAudioFormatLabels(for: candidate)
        playFromBeginning(url: candidate.url)
        return true
    }

    private func startArtworkVideoProcessingIfNeeded(
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
            self.logAnimatedArtwork("Processing started for id=\(mediaID)")

            do {
                guard let motionArtwork = await self.resolveMotionArtworkSource(
                    for: mediaID,
                    title: title,
                    artist: artist,
                    albumName: albumName
                ) else {
                    self.logAnimatedArtwork("No Animated Artwork found for id=\(mediaID)")
                    return
                }

                self.logAnimatedArtwork("Animated Artwork source found for id=\(mediaID): \(motionArtwork.sourceHLSURL.absoluteString)")

                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }

                self.logAnimatedArtwork("Preparing motion artwork for id=\(mediaID)")
                self.artworkVideoStatus = .processing

                let localVideoURL = try await self.artworkVideoProcessor.prepareVideo(
                    for: mediaID,
                    cacheID: motionArtwork.videoCacheID,
                    sourceHLSURL: motionArtwork.sourceHLSURL,
                    progress: { progress in
                        progressBridge.report(progress)
                    }
                )

                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }

                self.animatedArtworkVideoURL = localVideoURL
                self.artworkVideoProgress = 1
                self.artworkVideoStatus = .ready
                self.artworkVideoError = nil
                self.logAnimatedArtwork("Artwork found, transcoded, and loaded for id=\(mediaID): \(localVideoURL.lastPathComponent)")
                self.updateNowPlayingMetadata(force: true)
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
                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }

                self.animatedArtworkVideoURL = nil
                self.artworkVideoProgress = nil
                self.artworkVideoStatus = .failed
                self.artworkVideoError = error.localizedDescription
                self.logAnimatedArtwork("Artwork found but failed transcoding for id=\(mediaID): \(error.localizedDescription)")
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

    private func observeCurrentItemStatus(_ item: AVPlayerItem) {
        currentItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }

            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self.logPlayback("AVPlayerItem ready to play")
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
                    print("❌ PlayerViewModel: AVPlayerItem failed: \(errorMessage)")

                    if self.attemptNextPlaybackCandidateIfAvailable(errorMessage: errorMessage) {
                        return
                    }

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

                    self.isPlaying = false
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
            if statusCode != 0 {
                return statusCode
            }
        }

        return nil
    }

    private func observeCurrentItemEnd(_ item: AVPlayerItem) {
        removeCurrentItemEndObserver()
        currentItemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.advanceToNextQueueEntry(triggeredByPlaybackEnd: true)
            }
        }
    }

    private func removeCurrentItemEndObserver() {
        if let currentItemEndObserver {
            NotificationCenter.default.removeObserver(currentItemEndObserver)
            self.currentItemEndObserver = nil
        }
    }

    private func handlePlaybackPermissionFailureIfNeeded(
        errorMessage: String,
        statusCode: Int?,
        errorDomain: String?,
        errorCode: Int?
    ) -> Bool {
        guard let mediaID = currentVideoId else { return false }
        guard supportsYouTubeCandidateRecovery else { return false }

        guard shouldAttemptPlaybackRecovery(
            for: errorMessage,
            statusCode: statusCode,
            errorDomain: errorDomain,
            errorCode: errorCode
        ) else {
            return false
        }

        let currentAttemptCount = playbackRecoveryAttemptCounts[mediaID, default: 0]
        guard currentAttemptCount < PlaybackRecoveryPolicy.maxAttemptsPerMediaID else {
            return false
        }

        playbackRecoveryAttemptCounts[mediaID] = currentAttemptCount + 1
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = Task { [weak self] in
            guard let self else { return }

            do {
                await self.metadataCache.remove(mediaID)
                self.mediaCacheStore.invalidatePlayback(for: mediaID)
                let candidates = try await self.resolvePlaybackCandidates(forID: mediaID)

                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }
                self.configurePlaybackCandidates(for: mediaID, candidates: candidates)
                self.playCurrentPlaybackCandidate()
                self.logPlayback(
                    "Recovered playback with refreshed stream URL for id=\(mediaID), attempt=\(currentAttemptCount + 1), status=\(statusCode.map(String.init) ?? "n/a")"
                )
            } catch {
                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }
                self.isPlaying = false
                self.playbackError = error.localizedDescription
                self.updateNowPlayingPlaybackInfo(force: true)
                self.updateRemoteCommandState()
                print("❌ PlayerViewModel: Playback recovery failed for id=\(mediaID): \(error.localizedDescription)")
            }
        }

        return true
    }

    private func shouldAttemptPlaybackRecovery(
        for errorMessage: String,
        statusCode: Int?,
        errorDomain: String?,
        errorCode: Int?
    ) -> Bool {
        if let statusCode {
            if statusCode == 401 || statusCode == 403 || statusCode == 404 || statusCode == 410 || statusCode == 429 {
                return true
            }

            if statusCode >= 500 {
                return true
            }
        }

        if let errorDomain,
           let errorCode,
           errorDomain == NSURLErrorDomain {
            let recoverableCodes: Set<Int> = [-1100, -1102, -1011, -1009, -1005, -1004, -1003, -1001]
            if recoverableCodes.contains(errorCode) {
                return true
            }
        }

        if let errorDomain,
           let errorCode,
           errorDomain == AVFoundationErrorDomain {
            let recoverableCodes: Set<Int> = [-11800, -11819, -11850, -11867]
            if recoverableCodes.contains(errorCode) {
                return true
            }
        }

        let normalized = errorMessage.lowercased()
        return normalized.contains("permission")
            || normalized.contains("forbidden")
            || normalized.contains("403")
            || normalized.contains("not authorized")
            || normalized.contains("access denied")
            || normalized.contains("expired")
            || normalized.contains("signature")
            || normalized.contains("token")
            || normalized == "unknown error"
            || normalized.contains("failed to load")
            || normalized.contains("could not be loaded")
    }

    private func advanceQueueAfterUnrecoverableFailure(errorMessage: String) -> Bool {
        guard hasNextTrackInQueue else {
            return false
        }

        logPlayback("Advancing queue after unrecoverable failure: \(errorMessage)")
        advanceToNextQueueEntry(triggeredByPlaybackEnd: true)
        return true
    }

    private func handlePlaybackFailure(_ error: Error) {
        player.pause()
        isPlaying = false
        playbackError = error.localizedDescription
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
        print("❌ PlayerViewModel: Playback failed: \(error.localizedDescription)")
    }

    // MARK: - Internal Setup

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            MainActor.assumeIsolated {
                let previousDuration = self.duration
                let previousCanSkipBackward = self.canSkipBackward

                let nextCurrentTime = max(time.seconds, 0)
                if abs(self.currentTime - nextCurrentTime) > 0.0001 {
                    self.currentTime = nextCurrentTime
                }

                if let duration = self.player.currentItem?.duration.seconds,
                   duration.isFinite,
                   !duration.isNaN,
                   abs(self.duration - duration) > 0.0001 {
                    self.duration = duration
                }

                if self.canSkipBackward != previousCanSkipBackward {
                    self.updateRemoteCommandState()
                }

                if abs(self.duration - previousDuration) > 0.5 {
                    self.updateNowPlayingPlaybackInfo(force: true)
                }
            }
        }
    }

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

        reactivateAudioSessionIfNeeded()
        player.play()
        isPlaying = true
        updateNowPlayingPlaybackInfo(force: true)
        updateRemoteCommandState()
    }

    private func pause() {
        guard isPlaying else {
            updateRemoteCommandState()
            return
        }

        player.pause()
        isPlaying = false
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
