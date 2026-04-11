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

    private enum CachePolicy {
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

    enum LyricsState: Equatable {
        case idle
        case loading
        case synced
        case plain
        case unavailable(String)
    }

    struct TimedLyricLine: Identifiable, Equatable {
        let id: String
        let timestamp: TimeInterval
        let text: String

        init(timestamp: TimeInterval, text: String) {
            self.timestamp = timestamp
            self.text = text
            self.id = "\(timestamp)-\(text)"
        }
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

    private struct CachedRadioTrack: Sendable {
        let videoID: String
        let title: String
        let artist: String
        let albumName: String?
        let thumbnailURL: URL?
        let isExplicit: Bool

        init(
            videoID: String,
            title: String,
            artist: String,
            albumName: String?,
            thumbnailURL: URL?,
            isExplicit: Bool
        ) {
            self.videoID = videoID
            self.title = title
            self.artist = artist
            self.albumName = albumName
            self.thumbnailURL = thumbnailURL
            self.isExplicit = isExplicit
        }

        init(song: YouTubeMusicSong) {
            self.videoID = song.videoId
            self.title = song.title
            self.artist = song.artistsDisplay
            self.albumName = song.album
            self.thumbnailURL = song.thumbnailURL
            self.isExplicit = song.isExplicit
        }

        init?(cached: RadioSessionStore.CachedTrack) {
            let normalizedVideoID = cached.videoID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedVideoID.isEmpty else { return nil }

            self.videoID = normalizedVideoID
            self.title = cached.title
            self.artist = cached.artist
            self.albumName = cached.albumName
            self.thumbnailURL = cached.thumbnailURLString.flatMap { URL(string: $0) }
            self.isExplicit = cached.isExplicit
        }

        var persisted: RadioSessionStore.CachedTrack {
            RadioSessionStore.CachedTrack(
                videoID: videoID,
                title: title,
                artist: artist,
                albumName: albumName,
                thumbnailURLString: thumbnailURL?.absoluteString,
                isExplicit: isExplicit
            )
        }
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

    private enum PlaybackQueueEntry {
        case song(YouTubeMusicSong)
        case video(YouTubeVideo)
        case cachedRadio(CachedRadioTrack)
        case external(ExternalQueueTrack)

        var mediaID: String {
            switch self {
            case .song(let song):
                song.videoId
            case .video(let video):
                video.id
            case .cachedRadio(let track):
                track.videoID
            case .external(let track):
                track.mediaID
            }
        }
    }

    private struct MotionArtworkSourceResolution {
        let sourceHLSURL: URL
        let videoCacheID: String
    }

    private struct PreparedQueuePlayback {
        let mediaID: String
        let item: AVPlayerItem
        let playbackCandidates: [PlaybackCandidate]
        let preparedAt: Date
        let title: String
        let artist: String
        let artworkURL: URL?
        let streamingService: StreamingService
        let qualityLabel: String
        let codecLabel: String
        let albumName: String?
        let isExplicit: Bool
        let durationHint: Int?
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

    var currentSyncedLyricIndex: Int? {
        guard !syncedLyricsLines.isEmpty else { return nil }

        let playbackTime = max(currentTime, 0)
        if let firstTimestamp = syncedLyricsLines.first?.timestamp,
           playbackTime < firstTimestamp {
            return 0
        }

        return syncedLyricsLines.lastIndex { line in
            line.timestamp <= playbackTime
        }
    }

    var currentSyncedLyricText: String? {
        guard let index = currentSyncedLyricIndex,
              syncedLyricsLines.indices.contains(index) else {
            return nil
        }

        return syncedLyricsLines[index].text
    }

    var upcomingSyncedLyricText: String? {
        guard let index = currentSyncedLyricIndex else { return nil }
        let nextIndex = index + 1
        guard syncedLyricsLines.indices.contains(nextIndex) else { return nil }
        return syncedLyricsLines[nextIndex].text
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
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkVideoTask: Task<Void, Never>?
    private var lyricsLoadTask: Task<Void, Never>?
    private var playbackRecoveryTask: Task<Void, Never>?
    private var playbackRecoveryAttemptCounts: [String: Int] = [:]
    private var playbackCandidates: [PlaybackCandidate] = []
    private var playbackCandidateIndex: Int = 0
    private var playbackCandidatesMediaID: String?
    private var pendingPlaybackFormatOverride: (quality: String, codec: String)?
    private var currentAlbumNameHint: String?
    private var playbackQueue: [PlaybackQueueEntry] = [] {
        didSet {
            queuePreviewItems = playbackQueue.map { makeQueuePreviewItem(from: $0) }
        }
    }
    private var currentItemStatusObservation: NSKeyValueObservation?
    private var currentItemEndObserver: NSObjectProtocol?
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private let metadataCache: any VideoMetadataCaching
    private let itunes = iTunesKit()
    private let mediaCacheStore: MediaCacheStore
    private let settings: PrefetchSettings
    private let playbackMetricsStore: any PlaybackMetricsRecording
    private let streamingProviderSettings: any StreamingProviderSettingsReading
    private let radioSessionStore: RadioSessionStore
#if os(iOS)
    private let artworkColorExtractor: any ArtworkColorExtracting
#endif

#if os(iOS)
    private struct NowPlayingState: Equatable {
        var mediaID: String?
        var title: String = "Not Playing"
        var artist: String = ""
        var artworkURL: URL?
        var duration: Double = 0
        var elapsedTime: Double = 0
        var playbackRate: Float = 0
    }

    private struct CachedNowPlayingArtworkResource {
        let url: URL
        let data: Data
        let size: CGSize
    }

    private var nowPlayingState = NowPlayingState()
    private var lastPublishedNowPlayingState: NowPlayingState?
    private var currentArtworkResource: CachedNowPlayingArtworkResource?
    private var currentArtworkMediaID: String?
    private var artworkCache: [String: CachedNowPlayingArtworkResource] = [:]
    private var artworkAccentCache: [String: (artworkURL: URL, color: Color)] = [:]
    private var accentLoadTask: Task<Void, Never>?
#endif

#if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false
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
    private var preparedNextPlayback: PreparedQueuePlayback?
    private var nextPlaybackPreloadTask: Task<Void, Never>?
    private var preloadingNextMediaID: String?
    private var externalPayloadCache: [String: ExternalStreamPayload] = [:]
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
        let fallbackURL = URL(string: video.thumbnailURL ?? "")
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
#if canImport(TidalKit)
                let hiResPayload: ExternalStreamPayload?
                do {
                    if let cachedPayload = self.externalPayloadCache[mediaID],
                       cachedPayload.service == .tidal {
                        hiResPayload = cachedPayload
                    } else {
                        hiResPayload = try await self.resolveHiResTidalPayload(
                            title: displayTitle,
                            artist: displayArtist,
                            excludingMediaID: mediaID
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    hiResPayload = nil
                }

                if let hiResPayload {
                    if Task.isCancelled { return }
                    guard self.currentVideoId == targetMediaID else { return }

                    self.externalPayloadCache[mediaID] = hiResPayload
                    self.currentTitle = normalizedMusicDisplayTitle(hiResPayload.title, artist: hiResPayload.artist)
                    self.currentArtist = normalizedMusicDisplayArtist(hiResPayload.artist, title: hiResPayload.title)
                    self.currentImageURL = hiResPayload.artworkURL ?? thumbnailURL
                    self.currentStreamingServiceName = StreamingService.tidal.rawValue
                    self.currentAudioQualityLabel = hiResPayload.qualityLabel
                    self.currentAudioCodecLabel = hiResPayload.codecLabel
                    self.pendingPlaybackFormatOverride = (hiResPayload.qualityLabel, hiResPayload.codecLabel)

                    let hiResCandidate = PlaybackCandidate(
                        url: hiResPayload.streamURL,
                        streamKind: .audio,
                        mimeType: self.mimeTypeForCodecLabel(hiResPayload.codecLabel),
                        itag: nil,
                        expiresAt: nil,
                        isCompatible: true
                    )
                    let youtubeFallbackCandidates = (try? await self.resolvePlaybackCandidates(forID: mediaID)) ?? []

                    self.configurePlaybackCandidates(
                        for: mediaID,
                        candidates: [hiResCandidate] + youtubeFallbackCandidates
                    )
                    self.playCurrentPlaybackCandidate()
                    self.startArtworkVideoProcessingIfNeeded(
                        for: mediaID,
                        title: self.currentTitle,
                        artist: self.currentArtist,
                        albumName: albumName
                    )
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
                    self.preloadNextQueueEntryIfNeeded()

                    if self.settings.metricsEnabled {
                        let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                        await self.playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                    }

                    return
                }
#endif

                let candidates = try await self.resolvePlaybackCandidates(forID: mediaID)

                if Task.isCancelled { return }
                guard self.currentVideoId == targetMediaID else { return }

                self.configurePlaybackCandidates(for: mediaID, candidates: candidates)
                self.playCurrentPlaybackCandidate()
                self.startArtworkVideoProcessingIfNeeded(
                    for: mediaID,
                    title: displayTitle,
                    artist: displayArtist,
                    albumName: albumName
                )
                self.logPlayback("Started playback for song id=\(mediaID)")
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
                artworkURL: Self.normalizedQueueArtworkURL(from: video.thumbnailURL)
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

    private static func normalizedQueueArtworkURL(from rawValue: String?) -> URL? {
        guard var candidate = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return nil
        }

        if candidate.hasPrefix("//") {
            candidate = "https:" + candidate
        } else if !candidate.hasPrefix("http://") && !candidate.hasPrefix("https://") {
            candidate = "https://" + candidate
        }

        return URL(string: candidate)
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

        func similarity(_ lhs: String, _ rhs: String) -> Double {
            let left = Set(lhs.split(separator: " ").map(String.init))
            let right = Set(rhs.split(separator: " ").map(String.init))
            guard !left.isEmpty, !right.isEmpty else { return 0 }
            return Double(left.intersection(right).count) / Double(max(left.count, right.count))
        }

        return candidates.max { lhs, rhs in
            let lhsTitle = normalizedMusicDisplayTitle(lhs.title, artist: lhs.artistsDisplay).lowercased()
            let rhsTitle = normalizedMusicDisplayTitle(rhs.title, artist: rhs.artistsDisplay).lowercased()
            let lhsArtist = normalizedMusicDisplayArtist(lhs.artistsDisplay, title: lhs.title).lowercased()
            let rhsArtist = normalizedMusicDisplayArtist(rhs.artistsDisplay, title: rhs.title).lowercased()

            let lhsScore = (0.7 * similarity(lhsTitle, targetTitle)) + (0.3 * similarity(lhsArtist, targetArtist))
            let rhsScore = (0.7 * similarity(rhsTitle, targetTitle)) + (0.3 * similarity(rhsArtist, targetArtist))
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

    private func preloadNextQueueEntryIfNeeded() {
        guard let queuePosition else {
            preparedNextPlayback = nil
            nextPlaybackPreloadTask?.cancel()
            nextPlaybackPreloadTask = nil
            preloadingNextMediaID = nil
            return
        }

        let nextIndex = queuePosition + 1
        guard playbackQueue.indices.contains(nextIndex) else {
            preparedNextPlayback = nil
            nextPlaybackPreloadTask?.cancel()
            nextPlaybackPreloadTask = nil
            preloadingNextMediaID = nil
            return
        }

        let nextEntry = playbackQueue[nextIndex]
        if preparedNextPlayback?.mediaID == nextEntry.mediaID {
            return
        }

        if preloadingNextMediaID == nextEntry.mediaID,
           nextPlaybackPreloadTask != nil {
            return
        }

        preparedNextPlayback = nil
        nextPlaybackPreloadTask?.cancel()
        preloadingNextMediaID = nextEntry.mediaID
        nextPlaybackPreloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.preloadingNextMediaID == nextEntry.mediaID {
                    self.preloadingNextMediaID = nil
                }
            }

            let prepared = await self.prepareQueuePlayback(for: nextEntry)
            guard !Task.isCancelled,
                  let prepared,
                  let currentQueuePosition = self.queuePosition else {
                return
            }

            let expectedIndex = currentQueuePosition + 1
            guard self.playbackQueue.indices.contains(expectedIndex),
                  self.playbackQueue[expectedIndex].mediaID == prepared.mediaID else {
                return
            }

            self.preparedNextPlayback = prepared
        }
    }

    private func prepareQueuePlayback(for entry: PlaybackQueueEntry) async -> PreparedQueuePlayback? {
        do {
            switch entry {
            case .song(let song):
#if canImport(TidalKit)
                let cachedHiResPayload = externalPayloadCache[song.videoId].flatMap { payload -> ExternalStreamPayload? in
                    guard payload.service == .tidal else { return nil }
                    return payload
                }

                let hiResPayload: ExternalStreamPayload?
                if let cachedHiResPayload {
                    hiResPayload = cachedHiResPayload
                } else {
                    hiResPayload = try await resolveHiResTidalPayload(
                        title: song.title,
                        artist: song.artistsDisplay,
                        excludingMediaID: song.videoId
                    )
                }

                if let hiResPayload {
                    externalPayloadCache[song.videoId] = hiResPayload
                    logPlayback("Prepared Hi-Res preload variant for id=\(song.videoId)")

                    let hiResCandidate = PlaybackCandidate(
                        url: hiResPayload.streamURL,
                        streamKind: .audio,
                        mimeType: mimeTypeForCodecLabel(hiResPayload.codecLabel),
                        itag: nil,
                        expiresAt: nil,
                        isCompatible: true
                    )
                    let youtubeFallbackCandidates = (try? await resolvePlaybackCandidates(forID: song.videoId)) ?? []

                    let prepared = PreparedQueuePlayback(
                        mediaID: song.videoId,
                        item: makePlayerItem(for: hiResPayload.streamURL, service: .tidal),
                        playbackCandidates: [hiResCandidate] + youtubeFallbackCandidates,
                        preparedAt: .now,
                        title: normalizedMusicDisplayTitle(hiResPayload.title, artist: hiResPayload.artist),
                        artist: normalizedMusicDisplayArtist(hiResPayload.artist, title: hiResPayload.title),
                        artworkURL: hiResPayload.artworkURL ?? song.thumbnailURL,
                        streamingService: .tidal,
                        qualityLabel: hiResPayload.qualityLabel,
                        codecLabel: hiResPayload.codecLabel,
                        albumName: song.album,
                        isExplicit: song.isExplicit,
                        durationHint: Self.lyricsDurationHint(from: song.duration)
                    )
                    debugQueuePreloadSelection(prepared, source: "tidal-hires")
                    return prepared
                }
#endif

                let candidates = try await resolvePlaybackCandidates(forID: song.videoId)
                guard let candidate = candidates.first else { return nil }
                let labels = playbackLabels(for: candidate)

                let prepared = PreparedQueuePlayback(
                    mediaID: song.videoId,
                    item: makePlayerItem(for: candidate.url, service: .youtubeMusic),
                    playbackCandidates: candidates,
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay),
                    artist: normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title),
                    artworkURL: song.thumbnailURL,
                    streamingService: .youtubeMusic,
                    qualityLabel: labels.quality,
                    codecLabel: labels.codec,
                    albumName: song.album,
                    isExplicit: song.isExplicit,
                    durationHint: Self.lyricsDurationHint(from: song.duration)
                )
                debugQueuePreloadSelection(prepared, source: "youtube-fallback")
                return prepared

            case .cachedRadio(let track):
#if canImport(TidalKit)
                let cachedHiResPayload = externalPayloadCache[track.videoID].flatMap { payload -> ExternalStreamPayload? in
                    guard payload.service == .tidal else { return nil }
                    return payload
                }

                let hiResPayload: ExternalStreamPayload?
                if let cachedHiResPayload {
                    hiResPayload = cachedHiResPayload
                } else {
                    hiResPayload = try await resolveHiResTidalPayload(
                        title: track.title,
                        artist: track.artist,
                        excludingMediaID: track.videoID
                    )
                }

                if let hiResPayload {
                    externalPayloadCache[track.videoID] = hiResPayload
                    logPlayback("Prepared Hi-Res preload variant for radio id=\(track.videoID)")

                    let hiResCandidate = PlaybackCandidate(
                        url: hiResPayload.streamURL,
                        streamKind: .audio,
                        mimeType: mimeTypeForCodecLabel(hiResPayload.codecLabel),
                        itag: nil,
                        expiresAt: nil,
                        isCompatible: true
                    )
                    let youtubeFallbackCandidates = (try? await resolvePlaybackCandidates(forID: track.videoID)) ?? []

                    let prepared = PreparedQueuePlayback(
                        mediaID: track.videoID,
                        item: makePlayerItem(for: hiResPayload.streamURL, service: .tidal),
                        playbackCandidates: [hiResCandidate] + youtubeFallbackCandidates,
                        preparedAt: .now,
                        title: normalizedMusicDisplayTitle(hiResPayload.title, artist: hiResPayload.artist),
                        artist: normalizedMusicDisplayArtist(hiResPayload.artist, title: hiResPayload.title),
                        artworkURL: hiResPayload.artworkURL ?? track.thumbnailURL,
                        streamingService: .tidal,
                        qualityLabel: hiResPayload.qualityLabel,
                        codecLabel: hiResPayload.codecLabel,
                        albumName: track.albumName,
                        isExplicit: track.isExplicit,
                        durationHint: nil
                    )
                    debugQueuePreloadSelection(prepared, source: "radio-tidal-hires")
                    return prepared
                }
#endif

                let candidates = try await resolvePlaybackCandidates(forID: track.videoID)
                guard let candidate = candidates.first else { return nil }
                let labels = playbackLabels(for: candidate)

                let prepared = PreparedQueuePlayback(
                    mediaID: track.videoID,
                    item: makePlayerItem(for: candidate.url, service: .youtubeMusic),
                    playbackCandidates: candidates,
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(track.title, artist: track.artist),
                    artist: normalizedMusicDisplayArtist(track.artist, title: track.title),
                    artworkURL: track.thumbnailURL,
                    streamingService: .youtubeMusic,
                    qualityLabel: labels.quality,
                    codecLabel: labels.codec,
                    albumName: track.albumName,
                    isExplicit: track.isExplicit,
                    durationHint: nil
                )
                debugQueuePreloadSelection(prepared, source: "radio-youtube-fallback")
                return prepared

            case .video(let video):
                let candidates = try await resolvePlaybackCandidates(forID: video.id)
                guard let candidate = candidates.first else { return nil }
                let labels = playbackLabels(for: candidate)

                let prepared = PreparedQueuePlayback(
                    mediaID: video.id,
                    item: makePlayerItem(for: candidate.url, service: .youtube),
                    playbackCandidates: candidates,
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                    artist: normalizedMusicDisplayArtist(video.author, title: video.title),
                    artworkURL: Self.normalizedQueueArtworkURL(from: video.thumbnailURL),
                    streamingService: .youtube,
                    qualityLabel: labels.quality,
                    codecLabel: labels.codec,
                    albumName: nil,
                    isExplicit: false,
                    durationHint: Self.lyricsDurationHint(from: video.lengthInSeconds)
                )
                debugQueuePreloadSelection(prepared, source: "youtube-video")
                return prepared

            case .external(let track):
                let normalizedMediaID = track.mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedMediaID.isEmpty else { return nil }

                let payload: ExternalStreamPayload
                if let cachedPayload = externalPayloadCache[normalizedMediaID] {
                    payload = cachedPayload
                } else {
                    payload = try await track.resolvePayload()
                    externalPayloadCache[normalizedMediaID] = payload
                }

                let streamingService = Self.streamingService(for: payload.service)
                let candidate = PlaybackCandidate(
                    url: payload.streamURL,
                    streamKind: .audio,
                    mimeType: mimeTypeForCodecLabel(payload.codecLabel),
                    itag: nil,
                    expiresAt: nil,
                    isCompatible: true
                )
                let prepared = PreparedQueuePlayback(
                    mediaID: normalizedMediaID,
                    item: makePlayerItem(for: payload.streamURL, service: streamingService),
                    playbackCandidates: [candidate],
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(payload.title, artist: payload.artist),
                    artist: normalizedMusicDisplayArtist(payload.artist, title: payload.title),
                    artworkURL: payload.artworkURL ?? track.artworkURL,
                    streamingService: streamingService,
                    qualityLabel: payload.qualityLabel,
                    codecLabel: payload.codecLabel,
                    albumName: nil,
                    isExplicit: track.isExplicit,
                    durationHint: nil
                )
                debugQueuePreloadSelection(prepared, source: "external-\(payload.service.rawValue)")
                return prepared
            }
        } catch {
            logPlayback("Queue preload failed for mediaID=\(entry.mediaID): \(error.localizedDescription)")
            return nil
        }
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

    private func debugQueuePreloadSelection(_ prepared: PreparedQueuePlayback, source: String) {
#if DEBUG
        print("[QUEUE]: {source: \(source), mediaID: \(prepared.mediaID), title: \(prepared.title), artist: \(prepared.artist), service: \(prepared.streamingService.rawValue), quality: \(prepared.qualityLabel), codec: \(prepared.codecLabel), queueSource: \(queueSource.rawValue), queuePosition: \(queuePosition ?? -1), queueCount: \(queueCount)}")
#endif
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

        let normalizedTargetTitle = normalizedHiResLookupText(title)
        let normalizedTargetArtist = normalizedHiResLookupText(artist)
        let searchResults = try await Monochrome.shared.content.searchTracks(query: query)

        let candidates = searchResults
            .prefix(20)
            .compactMap { track -> HiResLookupCandidate? in
                let mediaID = "tidal-\(track.id)"
                if mediaID == excludingMediaID {
                    return nil
                }

                let normalizedCandidateTitle = normalizedHiResLookupText(track.title)
                let normalizedCandidateArtist = normalizedHiResLookupText(track.artist?.name ?? "")

                let titleScore = tokenOverlapRatio(
                    lhs: normalizedCandidateTitle,
                    rhs: normalizedTargetTitle
                )
                guard titleScore >= 0.45 else {
                    return nil
                }

                let artistScore = tokenOverlapRatio(
                    lhs: normalizedCandidateArtist,
                    rhs: normalizedTargetArtist
                )
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

    private func normalizedHiResLookupText(_ value: String) -> String {
        let lowercased = value.lowercased()
        let stripped = lowercased.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )

        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenOverlapRatio(lhs: String, rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }

        let overlapCount = Double(lhsTokens.intersection(rhsTokens).count)
        let normalizer = Double(max(lhsTokens.count, rhsTokens.count))
        guard normalizer > 0 else { return 0 }

        return overlapCount / normalizer
    }

    private func tidalArtworkURL(from coverID: String?) -> URL? {
        guard let coverID, !coverID.isEmpty else { return nil }
        let formatted = coverID.replacingOccurrences(of: "-", with: "/")
        return URL(string: "https://resources.tidal.com/images/\(formatted)/320x320.jpg")
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

    private func playbackLabels(for candidate: PlaybackCandidate) -> (quality: String, codec: String) {
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

    private static func streamingService(for federatedService: FederatedService) -> StreamingService {
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

    private struct LyricsResolution {
        let syncedLines: [TimedLyricLine]
        let plainText: String?
        let attribution: String?
    }

    private func startLyricsResolution(
        mediaID: String,
        title: String,
        artist: String,
        albumName: String?,
        durationHint: Int?
    ) {
        lyricsLoadTask?.cancel()
        syncedLyricsLines = []
        plainLyricsText = nil
        lyricsAttribution = nil

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = Self.nonEmptyTrimmed(albumName)

        guard !normalizedTitle.isEmpty else {
            lyricsState = .idle
            return
        }

#if canImport(LyricsKit)
        lyricsState = .loading
        lyricsLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let resolvedLyrics = try await Self.resolveLyrics(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    albumName: normalizedAlbum,
                    durationHint: durationHint
                )

                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }

                self.syncedLyricsLines = resolvedLyrics.syncedLines
                self.plainLyricsText = resolvedLyrics.plainText
                self.lyricsAttribution = resolvedLyrics.attribution

                if !resolvedLyrics.syncedLines.isEmpty {
                    self.lyricsState = .synced
                } else if let plainText = resolvedLyrics.plainText,
                          !plainText.isEmpty {
                    self.lyricsState = .plain
                } else {
                    self.lyricsState = .unavailable("Lyrics unavailable for this track.")
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.currentVideoId == mediaID else { return }
                self.lyricsState = .unavailable(error.localizedDescription)
            }
        }
#else
        lyricsState = .unavailable("LyricsKit is not linked to this target.")
#endif
    }

#if canImport(LyricsKit)
    private static func resolveLyrics(
        title: String,
        artist: String,
        albumName: String?,
        durationHint: Int?
    ) async throws -> LyricsResolution {
        let kit = LyricsKit.shared
        let artistName = nonEmptyTrimmed(artist)
        let album = nonEmptyTrimmed(albumName)

        if let durationHint,
           durationHint > 0,
           let artistName {
            let signatureAlbum = album ?? "Single"
            if let best = try await kit.bestLyrics(
                trackName: title,
                artistName: artistName,
                albumName: signatureAlbum,
                durationInSeconds: durationHint
            ) {
                let mapped = mapLyricsRecord(best)
                if !mapped.syncedLines.isEmpty || mapped.plainText != nil {
                    return mapped
                }
            }
        }

        let syncedCandidates = try await kit.searchSynced(
            trackName: title,
            artistName: artistName,
            albumName: album
        )

        if let syncedMatch = syncedCandidates.first {
            let mapped = mapLyricsRecord(syncedMatch)
            if !mapped.syncedLines.isEmpty || mapped.plainText != nil {
                return mapped
            }
        }

        let fallbackCandidates = try await kit.search(
            trackName: title,
            artistName: artistName,
            albumName: album
        )

        if let firstFallback = fallbackCandidates.first {
            return mapLyricsRecord(firstFallback)
        }

        return LyricsResolution(syncedLines: [], plainText: nil, attribution: nil)
    }

    private static func mapLyricsRecord(_ record: LyricsRecord) -> LyricsResolution {
        let syncedLines: [TimedLyricLine] = (record.parsedSyncedLyrics?.lines ?? [])
            .compactMap { line in
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TimedLyricLine(timestamp: line.timestamp, text: text)
            }

        var plainLyrics = nonEmptyTrimmed(record.plainLyrics)
        if plainLyrics == nil, record.instrumental {
            plainLyrics = "Instrumental"
        }

        let attributionParts = [
            nonEmptyTrimmed(record.artistName),
            nonEmptyTrimmed(record.trackName)
        ]
        .compactMap { $0 }
        let attribution = attributionParts.isEmpty ? nil : attributionParts.joined(separator: " • ")

        return LyricsResolution(
            syncedLines: syncedLines,
            plainText: plainLyrics,
            attribution: attribution
        )
    }
#endif

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func lyricsDurationHint(from duration: TimeInterval?) -> Int? {
        guard let duration,
              duration.isFinite,
              duration > 0 else {
            return nil
        }

        return Int(duration.rounded())
    }

    private static func lyricsDurationHint(from rawDuration: String) -> Int? {
        let trimmed = rawDuration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directSeconds = Int(trimmed), directSeconds > 0 {
            return directSeconds
        }

        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return (parts[0] * 60) + parts[1]
        }
        if parts.count == 3 {
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        }

        return nil
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

    private func resolvePlaybackCandidates(forID id: String) async throws -> [PlaybackCandidate] {
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

    private func makePlayerItem(for url: URL, service: StreamingService? = nil) -> AVPlayerItem {
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

    private func mimeTypeForCodecLabel(_ codecLabel: String) -> String? {
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

        let qualityLabel: String
        switch candidate.streamKind {
        case .hls:
            qualityLabel = "Adaptive"
        case .muxed:
            qualityLabel = "Muxed"
        case .audio:
            qualityLabel = "Direct Audio"
        }

        let mime = candidate.mimeType?.lowercased() ?? ""
        let codecLabel: String
        if mime.contains("flac") {
            codecLabel = "FLAC"
        } else if mime.contains("aac") || mime.contains("mp4a") || mime.contains("m4a") {
            codecLabel = "AAC"
        } else if mime.contains("mpeg") || mime.contains("mp3") {
            codecLabel = "MP3"
        } else if mime.contains("opus") {
            codecLabel = "Opus"
        } else if candidate.streamKind == .hls {
            codecLabel = "HLS"
        } else {
            codecLabel = "Unknown"
        }

        currentAudioQualityLabel = qualityLabel
        currentAudioCodecLabel = codecLabel
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

    private func logAnimatedArtwork(_ message: String) {
#if DEBUG
        guard Diagnostics.verboseArtworkLogsEnabled else { return }
        print("🖼️ PlayerViewModel: \(message)")
#endif
    }

    private func logPlayback(_ message: String) {
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

    // MARK: - Audio Session

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("❌ PlayerViewModel: Failed to configure audio session: \(error)")
        }
        #endif
    }

    private func configurePlayerForBackgroundPlayback() {
        #if os(iOS)
        player.automaticallyWaitsToMinimizeStalling = true
        if #available(iOS 14.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        #endif
    }

    #if os(iOS)
    private func setupAudioLifecycleObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self.handleAudioSessionInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self.handleAudioRouteChange(reasonValue: reasonValue)
            }
        }
    }

    private func handleAudioSessionInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            VolumeButtonSkipController.shared.cancelActiveHold()
            wasPlayingBeforeInterruption = isPlaying
            player.pause()
            isPlaying = false
            updateNowPlayingPlaybackInfo(force: true)
            updateRemoteCommandState()
            print("⚠️ PlayerViewModel: Audio interruption began")

        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            let shouldResume = options.contains(.shouldResume)

            if shouldResume && wasPlayingBeforeInterruption {
                reactivateAudioSessionIfNeeded()
                player.play()
                isPlaying = true
                print("✅ PlayerViewModel: Resumed after interruption")
            }

            updateNowPlayingPlaybackInfo(force: true)
            updateRemoteCommandState()
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            if isPlaying {
                player.pause()
                isPlaying = false
                updateNowPlayingPlaybackInfo(force: true)
                updateRemoteCommandState()
                print("⚠️ PlayerViewModel: Paused because audio route became unavailable")
            }
        case .newDeviceAvailable:
            if isPlaying {
                reactivateAudioSessionIfNeeded()
                player.play()
            }
        case .routeConfigurationChange:
            reactivateAudioSessionIfNeeded()
        default:
            break
        }
    }

    private func reactivateAudioSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ PlayerViewModel: Failed to reactivate audio session: \(error)")
        }
    }
    #else
    private func setupAudioLifecycleObservers() {}
    private func reactivateAudioSessionIfNeeded() {}
    #endif

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

    private func updateRemoteCommandState() {
        remoteCommandCenter.playCommand.isEnabled = !isPlaying && currentVideoId != nil
        remoteCommandCenter.pauseCommand.isEnabled = isPlaying
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = currentVideoId != nil
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = currentVideoId != nil
        remoteCommandCenter.nextTrackCommand.isEnabled = canSkipForward
        remoteCommandCenter.previousTrackCommand.isEnabled = canSkipBackward
    }

    // MARK: - Now Playing Info

    #if os(iOS)
    private func updateNowPlayingMetadata(force: Bool = true) {
        nowPlayingState.mediaID = currentVideoId
        nowPlayingState.title = currentTitle
        nowPlayingState.artist = currentArtist
        nowPlayingState.artworkURL = currentImageURL
        updateNowPlayingPlaybackInfo(force: force)
    }

    private func updateNowPlayingPlaybackInfo(force: Bool = false) {
        nowPlayingState.elapsedTime = currentElapsedTimeSnapshot()
        nowPlayingState.duration = currentDurationSnapshot()
        nowPlayingState.playbackRate = currentPlaybackRateSnapshot()

        publishNowPlayingInfo(force: force)
    }

    private func publishNowPlayingInfo(force: Bool) {
        guard force || nowPlayingState != lastPublishedNowPlayingState else {
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingState.title,
            MPMediaItemPropertyArtist: nowPlayingState.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: nowPlayingState.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: nowPlayingState.playbackRate
        ]

        if nowPlayingState.duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = nowPlayingState.duration
        }

        if currentArtworkMediaID == nowPlayingState.mediaID,
           let currentArtworkResource,
           let mediaArtwork = Self.makeMediaItemArtwork(from: currentArtworkResource) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaArtwork
        }

        if #available(iOS 26.0, *),
           let mediaID = nowPlayingState.mediaID,
           let animatedArtworkVideoURL,
           currentVideoId == mediaID,
           let animatedArtwork = Self.makeAnimatedArtwork(
                mediaID: mediaID,
                videoURL: animatedArtworkVideoURL,
                previewData: currentArtworkMediaID == mediaID ? currentArtworkResource?.data : nil
           ) {
            let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
            if supportedKeys.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) {
                nowPlayingInfo[MPNowPlayingInfoProperty1x1AnimatedArtwork] = animatedArtwork
            }
            if supportedKeys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) {
                nowPlayingInfo[MPNowPlayingInfoProperty3x4AnimatedArtwork] = animatedArtwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        lastPublishedNowPlayingState = nowPlayingState
    }

    private func currentElapsedTimeSnapshot() -> Double {
        let playerTime = player.currentTime().seconds
        if playerTime.isFinite && !playerTime.isNaN && playerTime >= 0 {
            return playerTime
        }

        return max(currentTime, 0)
    }

    private func currentDurationSnapshot() -> Double {
        if duration.isFinite && !duration.isNaN && duration > 0 {
            return duration
        }

        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite,
           !itemDuration.isNaN,
           itemDuration > 0 {
            return itemDuration
        }

        return 0
    }

    private func currentPlaybackRateSnapshot() -> Float {
        guard isPlaying else { return 0 }
        return player.rate > 0 ? player.rate : 1
    }

    private func applyCachedArtworkIfAvailable(for mediaID: String) {
        guard let cachedArtwork = artworkCache[mediaID] else {
            currentArtworkResource = nil
            currentArtworkMediaID = nil
            return
        }

        applyArtwork(cachedArtwork, for: mediaID, cacheInMemory: false)
    }

    private func applyArtwork(
        _ artwork: CachedNowPlayingArtworkResource,
        for mediaID: String,
        cacheInMemory: Bool
    ) {
        currentImageURL = artwork.url
        currentArtworkResource = artwork
        currentArtworkMediaID = mediaID
        updateAccentColor(from: artwork, mediaID: mediaID)

        if cacheInMemory {
            artworkCache[mediaID] = artwork
        }
    }

    private func updateAccentColor(from artwork: CachedNowPlayingArtworkResource, mediaID: String) {
        if let cachedAccent = artworkAccentCache[mediaID],
           cachedAccent.artworkURL == artwork.url {
            applyAccentColor(cachedAccent.color)
            return
        }

        accentLoadTask?.cancel()
        let artworkData = artwork.data
        let artworkURL = artwork.url

        accentLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let extractedAccent = await artworkColorExtractor.dominantColor(
                from: artworkData,
                cacheKey: artworkURL.absoluteString
            )

            guard !Task.isCancelled else { return }
            guard self.currentVideoId == mediaID else { return }

            self.artworkAccentCache[mediaID] = (artworkURL: artworkURL, color: extractedAccent)
            self.applyAccentColor(extractedAccent)
        }
    }

    private func applyAccentColor(_ color: Color) {
        currentAccentColor = color
        Color.updateDynamicAccent(color)
    }

    private func loadPersistentArtworkIfAvailable(for mediaID: String) async -> CachedNowPlayingArtworkResource? {
        guard let cachedArtwork = await mediaCacheStore.cachedLocalArtworkData(for: mediaID),
              let image = UIImage(data: cachedArtwork.data) else {
            return nil
        }

        return CachedNowPlayingArtworkResource(
            url: cachedArtwork.url,
            data: cachedArtwork.data,
            size: image.size
        )
    }

    private func persistArtwork(_ artwork: CachedNowPlayingArtworkResource, mediaID: String) async {
        _ = await mediaCacheStore.saveArtworkData(
            artwork.data,
            mediaID: mediaID,
            sourceURL: artwork.url
        )
    }

    private func loadNowPlayingArtwork(for mediaID: String, title: String, artist: String, fallbackURL: URL?) {
        artworkLoadTask?.cancel()

        let artworkTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let artworkArtist = normalizedMusicDisplayArtist(artist, title: title)
        let fallbackArtworkURL = fallbackURL

        artworkLoadTask = Task { [weak self, itunes] in
            guard let self else { return }
            if Task.isCancelled { return }

            if let persistedArtwork = await self.loadPersistentArtworkIfAvailable(for: mediaID) {
                guard self.currentVideoId == mediaID else { return }
                self.applyArtwork(persistedArtwork, for: mediaID, cacheInMemory: true)
                self.updateNowPlayingMetadata(force: true)
                return
            }

            let fallbackTask = Task {
                await Self.fetchArtworkResource(from: fallbackArtworkURL)
            }
            let highQualityTask = Task<CachedNowPlayingArtworkResource?, Never> {
                if let cachedURL = self.mediaCacheStore.cachedHighQualityArtworkURL(
                    for: mediaID,
                    maxAge: CachePolicy.highQualityArtworkTTL
                ) {
                    if let cachedArtwork = await Self.fetchArtworkResource(from: cachedURL) {
                        return cachedArtwork
                    }
                }

                if let highQualityURL = await Self.resolveHighQualityArtworkURL(
                    using: itunes,
                    title: artworkTitle,
                    artist: artworkArtist
                ) {
                    self.mediaCacheStore.saveHighQualityArtworkURL(highQualityURL, for: mediaID)
                    return await Self.fetchArtworkResource(from: highQualityURL)
                }

                return nil
            }

            if let fallbackArtwork = await fallbackTask.value {
                guard self.currentVideoId == mediaID else { return }
                guard self.currentArtworkMediaID != mediaID else { return }

                self.applyArtwork(fallbackArtwork, for: mediaID, cacheInMemory: false)
                self.updateNowPlayingMetadata(force: true)
                await self.persistArtwork(fallbackArtwork, mediaID: mediaID)
            }

            if let highQualityArtwork = await highQualityTask.value {
                guard self.currentVideoId == mediaID else { return }

                self.applyArtwork(highQualityArtwork, for: mediaID, cacheInMemory: true)
                self.updateNowPlayingMetadata(force: true)
                await self.persistArtwork(highQualityArtwork, mediaID: mediaID)
            }
        }
    }

    nonisolated private static func resolveHighQualityArtworkURL(using itunes: iTunesKit, title: String, artist: String) async -> URL? {
        do {
            let searchTitle = normalizedMusicDisplayTitle(title, artist: artist)
            let searchArtist = normalizedMusicDisplayArtist(artist, title: title)
            let response = try await itunes.search(term: "\(searchTitle) \(searchArtist)", country: "us", media: "music", limit: 1)
            return normalizedITunesArtworkURL(from: response.results.first?.artworkUrl100)
        } catch {
            return nil
        }
    }

    private func resolveMotionArtworkSource(
        for mediaID: String,
        title: String,
        artist: String,
        albumName: String?
    ) async -> MotionArtworkSourceResolution? {
        let searchTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let searchArtist = normalizedMusicDisplayArtist(artist, title: title)
        let localAlbumArtistCacheKey = normalizedMotionArtworkAlbumCacheKey(
            albumName: albumName,
            artistName: searchArtist
        )
        let localAlbumOnlyCacheKey = normalizedMotionArtworkAlbumCacheKey(
            albumName: albumName,
            artistName: nil
        )
        let localAlbumCacheKeys = [localAlbumArtistCacheKey, localAlbumOnlyCacheKey].compactMap { $0 }

        if let cachedURL = mediaCacheStore.cachedMotionArtworkSourceURL(
            for: mediaID,
            maxAge: CachePolicy.motionArtworkSourceTTL
        ) {
            logAnimatedArtwork("Motion artwork source cache hit (media) for id=\(mediaID)")
            return MotionArtworkSourceResolution(
                sourceHLSURL: cachedURL,
                videoCacheID: motionArtworkVideoCacheID(
                    mediaID: mediaID,
                    albumCacheKey: localAlbumArtistCacheKey ?? localAlbumOnlyCacheKey,
                    sourceURL: cachedURL
                )
            )
        }

        if let albumHit = mediaCacheStore.cachedMotionArtworkSourceURL(
            forAlbumKeys: localAlbumCacheKeys,
            maxAge: CachePolicy.motionArtworkSourceTTL
        ) {
            logAnimatedArtwork("Motion artwork source cache hit (album key=\(albumHit.albumKey)) for id=\(mediaID)")
            mediaCacheStore.saveMotionArtworkSourceURL(albumHit.url, for: mediaID)
            return MotionArtworkSourceResolution(
                sourceHLSURL: albumHit.url,
                videoCacheID: motionArtworkVideoCacheID(
                    mediaID: mediaID,
                    albumCacheKey: albumHit.albumKey,
                    sourceURL: albumHit.url
                )
            )
        }

        guard let resolution = await Self.resolveMotionArtwork(
            using: itunes,
            title: searchTitle,
            artist: searchArtist
        ) else {
            return nil
        }

        mediaCacheStore.saveMotionArtworkSourceURL(resolution.sourceURL, for: mediaID)

        var albumKeysToPersist = localAlbumCacheKeys
        let collectionCacheKey = motionArtworkCollectionCacheKey(collectionID: resolution.collectionID)
        if let collectionCacheKey {
            albumKeysToPersist.append(collectionCacheKey)
        }
        let catalogAlbumCacheKey = motionArtworkCatalogAlbumCacheKey(catalogAlbumID: resolution.catalogAlbumID)
        if let catalogAlbumCacheKey {
            albumKeysToPersist.append(catalogAlbumCacheKey)
        }
        mediaCacheStore.saveMotionArtworkSourceURL(resolution.sourceURL, forAlbumKeys: albumKeysToPersist)

        let selectedAlbumKey = catalogAlbumCacheKey
            ?? collectionCacheKey
            ?? localAlbumArtistCacheKey
            ?? localAlbumOnlyCacheKey
        logAnimatedArtwork(
            "Motion artwork source fetched from iTunes for id=\(mediaID) collection=\(resolution.collectionID.map(String.init) ?? "none")"
        )
        return MotionArtworkSourceResolution(
            sourceHLSURL: resolution.sourceURL,
            videoCacheID: motionArtworkVideoCacheID(
                mediaID: mediaID,
                albumCacheKey: selectedAlbumKey,
                sourceURL: resolution.sourceURL
            )
        )
    }

    nonisolated private static func resolveMotionArtwork(
        using itunes: iTunesKit,
        title: String,
        artist: String
    ) async -> iTunesMotionArtworkResolution? {
        do {
            return try await itunes.resolveMotionArtwork(
                term: "\(title) \(artist)",
                country: "us"
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func fetchArtworkResource(from url: URL?) async -> CachedNowPlayingArtworkResource? {
        guard let url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            return CachedNowPlayingArtworkResource(url: url, data: data, size: image.size)
        } catch {
            return nil
        }
    }

    nonisolated private static func makeMediaItemArtwork(from resource: CachedNowPlayingArtworkResource) -> MPMediaItemArtwork? {
        let imageData = resource.data
        let boundsSize = resource.size

        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            UIImage(data: imageData) ?? UIImage()
        }
    }

    @available(iOS 26.0, *)
    nonisolated private static func makeAnimatedArtwork(
        mediaID: String,
        videoURL: URL,
        previewData: Data?
    ) -> MPMediaItemAnimatedArtwork? {
        guard videoURL.isFileURL else {
            return nil
        }

        let artworkID = "\(mediaID)-\(videoURL.lastPathComponent)"
        return MPMediaItemAnimatedArtwork(
            artworkID: artworkID,
            previewImageRequestHandler: { requestedSize in
                guard let previewData,
                      let image = UIImage(data: previewData) else {
                    return nil
                }

                return makeAnimatedArtworkPreviewImage(
                    from: image,
                    requestedSize: requestedSize
                )
            },
            videoAssetFileURLRequestHandler: { _ in
                videoURL
            }
        )
    }

    @available(iOS 26.0, *)
    nonisolated private static func makeAnimatedArtworkPreviewImage(
        from image: UIImage,
        requestedSize: CGSize
    ) -> UIImage {
        let targetSize = normalizedAnimatedArtworkPreviewSize(
            requestedSize,
            fallbackSize: image.size
        )

        guard targetSize.width > 0,
              targetSize.height > 0,
              image.size.width > 0,
              image.size.height > 0 else {
            return image
        }

        let sourceAspectRatio = image.size.width / image.size.height
        let targetAspectRatio = targetSize.width / targetSize.height

        let drawRect: CGRect
        if sourceAspectRatio > targetAspectRatio {
            let scaledHeight = targetSize.height
            let scaledWidth = scaledHeight * sourceAspectRatio
            drawRect = CGRect(
                x: (targetSize.width - scaledWidth) / 2,
                y: 0,
                width: scaledWidth,
                height: scaledHeight
            )
        } else {
            let scaledWidth = targetSize.width
            let scaledHeight = scaledWidth / sourceAspectRatio
            drawRect = CGRect(
                x: 0,
                y: (targetSize.height - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale > 0 ? image.scale : 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: drawRect)
        }
    }

    @available(iOS 26.0, *)
    nonisolated private static func normalizedAnimatedArtworkPreviewSize(
        _ requestedSize: CGSize,
        fallbackSize: CGSize
    ) -> CGSize {
        if requestedSize.width > 0,
           requestedSize.height > 0,
           requestedSize.width.isFinite,
           requestedSize.height.isFinite {
            return requestedSize
        }

        if fallbackSize.width > 0,
           fallbackSize.height > 0,
           fallbackSize.width.isFinite,
           fallbackSize.height.isFinite {
            return fallbackSize
        }

        return CGSize(width: 512, height: 512)
    }
    #else
    private func resolveMotionArtworkSource(
        for mediaID: String,
        title: String,
        artist: String,
        albumName: String?
    ) async -> MotionArtworkSourceResolution? {
        _ = mediaID
        _ = title
        _ = artist
        _ = albumName
        return nil
    }

    private func updateNowPlayingMetadata(force: Bool = true) {}
    private func updateNowPlayingPlaybackInfo(force: Bool = false) {}
    private func publishNowPlayingInfo(force: Bool) {}
    #endif
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
