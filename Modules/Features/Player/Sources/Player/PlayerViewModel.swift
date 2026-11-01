//
//  PlayerViewModel.swift
//  Player
//
//  Coordinates the playback components. Implements none of them.
//

import Foundation
import Models
import Observation
import PlaybackCore
import ProviderSDK
import SwiftUI
import Utilities

/// Wires the playback components together and exposes commands to the UI.
///
/// The previous `PlayerViewModel` was 1,794 lines plus seven extensions, and *implemented* queue
/// management, search, result scoring, stream resolution, quality ranking, artwork processing,
/// lyrics aggregation, and provider-specific branching. This one owns none of that. It holds
/// references, forwards calls, and keeps the published state objects in step.
///
/// State lives on the four objects from `Models`, split by update frequency rather than by
/// feature, so a 30 Hz position tick does not invalidate the whole player UI. See
/// `PlayerState.swift`.
@MainActor
@Observable
public final class PlayerViewModel: PlaybackCommands {
    // MARK: Published state

    public let nowPlaying: NowPlayingState
    public let transport: TransportState
    public let progress: ProgressState
    public let lyrics: LyricsPresentation

    // MARK: Components

    public let queue: PlaybackQueue

    /// What the expanded player is showing: artwork, lyrics, or the queue.
    ///
    /// Pure presentation state, owned here because the player's chrome toggles it from more than
    /// one place. A single case makes the three states mutually exclusive by construction.
    public var nowPlayingMode: NowPlayingMode = .artwork
    private let engine: PlaybackEngine
    private let resolver: PlaybackResolver
    private var nowPlayingCenter: NowPlayingCenter?

    /// The source registry, kept so diagnostics can name the source that actually served a stream.
    /// Which source plays a track is decided during resolution, so it cannot be read from the ref.
    private let sources: SourceRegistry

    /// Guards against an in-flight resolve for a track the user has already skipped past.
    private var loadTask: Task<Void, Never>?

    /// Monotonic id for the current playback request, so a slow resolve for a track the user has
    /// already left cannot describe the active stream.
    @ObservationIgnored private var loadGeneration = 0

    /// What playback is actually using, guarded by the request id.
    ///
    /// Observed (not `@ObservationIgnored`) so `activeStreamState` below can be a computed property
    /// that SwiftUI tracks — the macro instruments the stored struct, and reading it through the
    /// computed property registers the dependency.
    private var activeStream = ActiveStreamTracker()

    /// The active stream, for the diagnostics label and the settings detail view.
    ///
    /// Reflects the **resolved candidate playback was handed**, including a fallback that replaced
    /// the ranked first choice — never the track the user tapped, the canonical song, or the
    /// candidate that failed.
    public var activeStreamState: ActiveStreamState {
        activeStream.state
    }

    public init(sources: SourceRegistry) {
        let nowPlaying = NowPlayingState()
        let transport = TransportState()
        let progress = ProgressState()

        self.nowPlaying = nowPlaying
        self.transport = transport
        self.progress = progress
        self.lyrics = LyricsPresentation()
        self.queue = PlaybackQueue()
        self.engine = PlaybackEngine(progress: progress, transport: transport)
        self.resolver = PlaybackResolver(sources: sources)
        self.sources = sources

        AudioSession.configure()
        wireEngineCallbacks()

        let center = NowPlayingCenter(commands: self)
        center.registerCommands()
        self.nowPlayingCenter = center
    }

    // MARK: - PlaybackCommands

    public func togglePlayPause() {
        engine.togglePlayPause()
        publishNowPlaying()
    }

    public func skipToNext() {
        guard let next = queue.advance() else {
            engine.stop()
            // There is no active stream to describe any more.
            activeStream.stop()
            // Nothing is playing, so there is no item length to report either. Leaving the last
            // track's observed duration here would describe audio that is no longer loaded.
            clearNowPlaying()
            publishNowPlaying()
            return
        }
        start(next)
    }

    public func skipToPrevious() {
        // Restart the current track when more than a few seconds in — what every music player does,
        // and what users expect from a double-tap on headphones.
        if progress.currentTime > 3 {
            engine.seek(to: 0)
            return
        }
        guard let previous = queue.retreat() else { return }
        start(previous)
    }

    public func seek(to timestamp: Double) {
        engine.seek(to: timestamp)
        publishNowPlaying()
    }

    public func cyclePlaybackMode() {
        queue.cycleMode()
        transport.playbackMode = queue.mode
        updateSkipAvailability()
        // Leaving a repeat mode can leave the queue about to end; top it up now, not next track.
        refillRadioIfNeeded()
    }

    public func load(_ ref: PlayableRef, preserveQueue: Bool) {
        if !preserveQueue {
            resetRadio()
        }
        queue.play(ref, preserveQueue: preserveQueue)
        start(ref)
    }

    public func setQueue(_ refs: [PlayableRef], startIndex: Int, shuffled: Bool) {
        resetRadio()
        queue.replace(with: refs, startIndex: startIndex, shuffled: shuffled)
        transport.playbackMode = queue.mode
        guard let current = queue.current else { return }
        start(current)
    }

    // MARK: - Playback

    /// Begins playing a ref: show its metadata immediately, resolve audio in the background.
    ///
    /// The display fields are painted from the ref before any network work, so tapping a track
    /// updates the UI instantly even when resolution takes a moment.
    private func start(_ ref: PlayableRef, keepingLadder: Bool = false) {
        loadTask?.cancel()
        // A retry of the current failure keeps its ladder, because the ladder is what bounds the
        // retries. `FallbackLadder` documents why resetting it here was an unbounded loop.
        if !keepingLadder {
            ladder.reset()
        }

        loadGeneration &+= 1
        let generation = loadGeneration

        // A new request resolves the previous request's stream state too, so a slow resolve for
        // the track the user just left cannot end up describing it.
        activeStream.begin(requestID: generation)

        nowPlaying.ref = ref
        nowPlaying.title = ref.title
        nowPlaying.artist = ref.artist
        nowPlaying.artworkURL = ref.artworkURL
        nowPlaying.duration = ref.durationSeconds ?? 0
        // The previous track's item length belongs to the previous track. Clearing it is what stops
        // a new track from briefly showing the old one's timeline — and what makes `timelineDuration`
        // fall back to the canonical value until this track's own item reports one.
        nowPlaying.observedItemDuration = nil
        nowPlaying.reportedStreamDuration = nil
        transport.isBuffering = true
        progress.currentTime = 0
        updateSkipAvailability()
        publishNowPlaying()
        loadLyrics(for: ref)

        loadTask = Task { [weak self] in
            guard let self else { return }
            let span = CisumSignpost.playback.begin("tap-to-play", ref.title)
            defer { CisumSignpost.playback.end("tap-to-play", state: span) }

            do {
                // Ranked best-first by the resolver: the adapter's own order is only its tie-break.
                let candidates = try await resolver.resolve(ref)
                guard !Task.isCancelled, nowPlaying.ref == ref else { return }
                guard let selected = candidates.first else {
                    throw ResolutionError.noMatch(source: ref.sourceID, title: ref.title, underlying: nil)
                }

                // Keep the rest so a failure can fall through to the next one rather than
                // skipping the track. YouTube legitimately returns an HLS manifest whose segments
                // are then rejected, while the progressive URL for the same track plays fine —
                // and ranking puts the progressive URL first, so that fallback is now the rare
                // case rather than the expected one.
                ladder.replaceCandidates(candidates)

                AudioSession.activate()
                engine.play(selected.stream)
                nowPlaying.reportedStreamDuration = PlaybackTimeline.usable(selected.stream.durationSeconds)
                publishActiveStream(selected, isFallback: false, requestID: generation)
                playingSeed = PlayableRef(
                    songID: ref.songID,
                    sourceID: selected.sourceID,
                    sourceTrackID: selected.sourceTrackID,
                    title: ref.title,
                    artist: ref.artist,
                    artworkURL: ref.artworkURL,
                    durationSeconds: ref.durationSeconds
                )
                refillRadioIfNeeded()
                publishNowPlaying()
            } catch {
                guard !Task.isCancelled, nowPlaying.ref == ref else { return }
                transport.isBuffering = false
                transport.isPlaying = false
                PerfLog.error("Could not play \(ref.title): \(error.localizedDescription)")
                // Ignored when a newer request has already taken over — the tracker holds the
                // request id, so a stale failure cannot blank the current stream.
                activeStream.fail(requestID: generation)
            }
        }
    }

    private func wireEngineCallbacks() {
        engine.onPlaybackEnded = { [weak self] in
            self?.skipToNext()
        }
        engine.onPlaybackFailed = { [weak self] _ in
            // A failure here is overwhelmingly an expired CDN URL rather than a dead track, so the
            // right response is to drop the cached URL and try the same ref again. Advancing the
            // queue on the first failure is what made tracks appear to skip themselves.
            self?.retryCurrentAfterFailure()
        }
        engine.onReadyForPlayback = { [weak self] item in
            guard let self else { return }
            // The length of the file that actually loaded, recorded as *observed* rather than written
            // over the canonical value. `AVPlayerItem.duration` is only meaningful once the item is
            // ready — this is that point, and an indefinite or not-yet-loaded duration is not a
            // duration, so it stays unknown (`isNumeric` excludes `.indefinite` and `.invalid`).
            nowPlaying.observedItemDuration = PlaybackTimeline.usable(item.duration.isNumeric ? item.duration.seconds : nil)
            publishNowPlaying()
        }
        engine.onTick = { [weak self] seconds in
            self?.updateLyricIndex(at: seconds)
        }
    }

    /// Records the stream that `PlaybackEngine` was just handed.
    private func publishActiveStream(_ candidate: PlaybackCandidate, isFallback: Bool, requestID: Int) {
        activeStream.activate(
            requestID: requestID,
            candidate: candidate,
            sourceDisplayName: sources.displayName(for: candidate.sourceID),
            isFallback: isFallback
        )
    }

    /// The current request's ranked alternatives and its bounded re-resolve.
    ///
    /// Owns both the fallback order and the termination condition; see `FallbackLadder`.
    private var ladder = FallbackLadder()

    private func retryCurrentAfterFailure() {
        guard let ref = nowPlaying.ref else { return }

        // A failure that arrives before this request has resolved belongs to the item being
        // replaced: `PlaybackEngine` keeps the outgoing item until the new one is ready, and its
        // status observer is item-scoped, so skipping tracks can deliver the old item's failure
        // while the new resolve is still in flight. Acting on it would re-resolve the track the user
        // just asked for and throw away the cached URL it was about to use.
        //
        // `startedFrom` is set by `replaceCandidates` and cleared only by `reset`, so it is exactly
        // "this request has a resolved candidate set" — and `engine.play` is unreachable before that.
        guard ladder.startedFrom != nil else { return }

        // Try the next candidate before doing anything more drastic. This is the cheap fix for the
        // common case: the manifest resolved but its segments were rejected, and the progressive
        // URL sitting behind it plays. The order is the ranker's, not the adapter's.
        if let next = ladder.next() {
            PerfLog.warning("Playback failed; falling back to \(next.stream.mimeType ?? next.stream.kind.rawValue)")
            AudioSession.activate()
            engine.play(next.stream)
            nowPlaying.reportedStreamDuration = PlaybackTimeline.usable(next.stream.durationSeconds)
            // The fallback's own metadata is what describes playback now — not the candidate that
            // failed, and not the one ranking preferred.
            publishActiveStream(next, isFallback: true, requestID: loadGeneration)
            publishNowPlaying()
            return
        }

        // No candidates left: the cached URL may simply have expired, so drop it and resolve once
        // more. `beginResolveRetry` grants that exactly once per failure episode — every candidate
        // tried, one fresh resolve, then stop.
        guard ladder.beginResolveRetry() else {
            // Every candidate failed and the fresh resolve failed too; the track is genuinely
            // unplayable, so move on rather than looping.
            activeStream.fail(requestID: loadGeneration)
            skipToNext()
            return
        }

        invalidateCachedStream?(ref)
        start(ref, keepingLadder: true)
    }

    /// Clears the now-playing track and both of its durations.
    private func clearNowPlaying() {
        nowPlaying.ref = nil
        nowPlaying.duration = 0
        nowPlaying.observedItemDuration = nil
        nowPlaying.reportedStreamDuration = nil
        lyricsTask?.cancel()
        lyricsRef = nil
        lyrics.state = .idle
        lyrics.syncedLines = []
        lyrics.plainText = nil
        lyrics.currentIndex = nil
        lyrics.attribution = nil
    }

    // MARK: - Radio

    /// Supplies the next page of a radio station seeded by a track. `nil` means nothing more.
    ///
    /// Injected, like `fetchLyrics`: which service builds the station is the composition root's
    /// decision, and Player never learns it.
    public var fetchRadio: (@MainActor (_ seed: PlayableRef, _ continuation: String?) async -> RadioBatch?)?

    /// Top the queue up when fewer than this many tracks remain after the current one.
    private static let radioLowWater = 3

    /// The station's seed — the first track that needed topping up after the user's own choice.
    @ObservationIgnored private var radioSeed: PlayableRef?
    @ObservationIgnored private var radioContinuation: String?
    @ObservationIgnored private var radioTask: Task<Void, Never>?
    /// The track that is playing, as the recording that actually resolved — what a station is built
    /// from. Not the tapped ref: that may be another service's id, or not a track id at all.
    @ObservationIgnored private var playingSeed: PlayableRef?
    /// Set when the station has nothing further, so a dry station is not asked again every track.
    @ObservationIgnored private var radioExhausted = false

    /// Entries the station added, by `queueKey` — the queue view's Autoplay section.
    public private(set) var autoplayKeys: Set<String> = []

    /// Whether the station keeps the queue going (Apple Music's ∞). Persisted; on by default.
    public private(set) var isAutoplayEnabled = UserDefaults.standard.object(forKey: autoplayDefaultsKey) as? Bool ?? true
    private static let autoplayDefaultsKey = "cisum.player.autoplay"

    static func queueKey(_ ref: PlayableRef) -> String {
        "\(ref.sourceID):\(ref.sourceTrackID)"
    }

    /// Turning autoplay off also removes what it queued, as Apple Music does; on, it refills at once.
    public func setAutoplay(_ enabled: Bool) {
        isAutoplayEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoplayDefaultsKey)
        guard !enabled else {
            refillRadioIfNeeded()
            return
        }
        if let position = queue.position {
            for index in stride(from: queue.count - 1, to: position, by: -1)
                where autoplayKeys.contains(Self.queueKey(queue.entries[index]))
            {
                queue.remove(at: index)
            }
        }
        resetRadio()
        updateSkipAvailability()
    }

    /// A new queue the user chose starts a new station.
    private func resetRadio() {
        radioTask?.cancel()
        radioTask = nil
        autoplayKeys.removeAll()
        radioSeed = nil
        radioContinuation = nil
        radioExhausted = false
    }

    /// Appends the station's next page when the queue is running out, so playback never just stops.
    ///
    /// Runs for every queue — a single tapped song, an album, a playlist — once its remaining tracks
    /// drop below `radioLowWater`; repeat modes never end, so they are left alone. The station is
    /// seeded by the first track that needed topping up and keeps that seed until the user picks a
    /// new queue. Duplicates are dropped by song identity (`PlaybackQueue.appendUnique`), so the same
    /// song arriving from another service, or already earlier in the queue, never lands twice.
    private func refillRadioIfNeeded() {
        guard isAutoplayEnabled, let fetchRadio, radioTask == nil, !radioExhausted,
              queue.mode == .off || queue.mode == .shuffle,
              let position = queue.position,
              queue.count - position - 1 < Self.radioLowWater,
              let seed = radioSeed ?? playingSeed
        else { return }

        radioTask = Task { [weak self] in
            let batch = await fetchRadio(seed, self?.radioContinuation)
            guard let self, !Task.isCancelled else { return }
            radioTask = nil
            radioSeed = seed
            radioContinuation = batch?.continuation

            let added = queue.appendUnique(batch?.refs ?? [])
            autoplayKeys.formUnion(added.map(Self.queueKey))
            if added.isEmpty, batch?.continuation == nil {
                radioExhausted = true
                PerfLog.info("Radio: station for '\(seed.title)' has nothing further")
                return
            }
            updateSkipAvailability()
            PerfLog.info("Radio: appended \(added.count) of \(batch?.refs.count ?? 0) track(s) seeded by '\(seed.title)'")
        }
    }

    // MARK: - Queue editing

    /// Shuffle on or off, independently of repeat's control (they share one mode underneath).
    public func toggleShuffle() {
        setMode(queue.mode == .shuffle ? .off : .shuffle)
    }

    /// Off → repeat all → repeat one → off.
    public func cycleRepeat() {
        let next: PlaybackMode = switch queue.mode {
        case .repeatAll: .repeatOne
        case .repeatOne: .off
        default: .repeatAll
        }
        setMode(next)
    }

    private func setMode(_ mode: PlaybackMode) {
        queue.mode = mode
        transport.playbackMode = mode
        updateSkipAvailability()
        refillRadioIfNeeded()
    }

    public func moveQueueEntry(from source: Int, to destination: Int) {
        queue.move(from: source, to: destination)
        updateSkipAvailability()
    }

    /// Removes an upcoming or played entry. The playing one stays.
    public func removeQueueEntry(at index: Int) {
        guard index != queue.position, queue.entries.indices.contains(index) else { return }
        autoplayKeys.remove(Self.queueKey(queue.entries[index]))
        queue.remove(at: index)
        updateSkipAvailability()
        refillRadioIfNeeded()
    }

    // MARK: - Lyrics

    /// Supplies lyrics for a track. `nil` means none were found.
    ///
    /// Injected, like `invalidateCachedStream`: Player displays lyrics, and where they come from is
    /// the composition root's decision.
    public var fetchLyrics: (@MainActor (PlayableRef) async -> LyricsContent?)?

    @ObservationIgnored private var lyricsTask: Task<Void, Never>?

    /// The track the current lyrics belong to. A retry of the same track keeps them.
    @ObservationIgnored private var lyricsRef: PlayableRef?

    private func loadLyrics(for ref: PlayableRef) {
        guard ref != lyricsRef else { return }
        lyricsRef = ref
        lyricsTask?.cancel()
        lyrics.syncedLines = []
        lyrics.plainText = nil
        lyrics.currentIndex = nil
        lyrics.attribution = nil

        guard let fetchLyrics else {
            lyrics.state = .unavailable("Lyrics are not available.")
            return
        }
        lyrics.state = .loading
        lyricsTask = Task { [weak self] in
            let content = await fetchLyrics(ref)
            // A skip while the request was in flight: these lyrics are for a track that has gone.
            guard let self, !Task.isCancelled, lyricsRef == ref else { return }
            apply(content)
        }
    }

    private func apply(_ content: LyricsContent?) {
        lyrics.attribution = content?.attribution
        if let content, !content.synced.isEmpty {
            lyrics.syncedLines = content.synced
            lyrics.plainText = content.plain
            lyrics.state = .synced
            updateLyricIndex(at: progress.currentTime)
        } else if let plain = content?.plain, !plain.isEmpty {
            lyrics.plainText = plain
            lyrics.state = .plain
        } else {
            lyrics.state = .unavailable("No lyrics found for this track.")
        }
    }

    /// Moves the highlighted line. Writes only when the line changes, so the lyrics view redraws
    /// once per line rather than on every tick.
    private func updateLyricIndex(at seconds: Double) {
        guard lyrics.state == .synced else { return }
        // ponytail: linear scan at 4 Hz over a few dozen lines; binary search if it ever shows up.
        let index = lyrics.syncedLines.lastIndex { $0.timestamp <= seconds }
        if index != lyrics.currentIndex {
            lyrics.currentIndex = index
        }
    }

    /// Drops the persisted stream URL for a ref after a playback failure.
    ///
    /// Injected rather than reached for directly, because persistence is the application's concern
    /// and Player does not import SwiftData.
    public var invalidateCachedStream: (@MainActor (PlayableRef) -> Void)?

    /// Fires whenever the published now-playing or transport state changes.
    ///
    /// Injected, not observed: Player does not know about the app's Discord presence, it just
    /// calls a closure the composition root supplies — same pattern as `invalidateCachedStream`.
    public var onNowPlayingChange: (@MainActor () -> Void)?

    // MARK: - Wiring for the composition root

    /// Supplies the persistence hooks the resolver needs.
    ///
    /// Player deliberately does not know about SwiftData; the app answers these two questions.
    public func configurePersistence(
        bindings: @escaping @MainActor (PlayableRef) -> [SongSource],
        persist: @escaping @MainActor (PlayableRef, SourceTrack, SourceStream) -> Void,
        invalidate: @escaping @MainActor (PlayableRef) -> Void
    ) {
        resolver.bindings = bindings
        resolver.persist = persist
        invalidateCachedStream = invalidate
    }

    // MARK: - Lifecycle

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background else { return }
        PlaybackControlSettings.shared.flushPendingWrites()
    }

    // MARK: - Private

    private func updateSkipAvailability() {
        transport.canSkipForward = queue.canSkipForward
        transport.canSkipBackward = queue.canSkipBackward
        nowPlayingCenter?.updateAvailability(
            canSkipForward: queue.canSkipForward,
            canSkipBackward: queue.canSkipBackward
        )
    }

    private func publishNowPlaying() {
        nowPlayingCenter?.update(
            nowPlaying: nowPlaying,
            transport: transport,
            currentTime: progress.currentTime
        )
        onNowPlayingChange?()
    }
}
