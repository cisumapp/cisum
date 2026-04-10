//
//  SearchViewModel.swift
//  cisum
//
//  Created by Aarav Gupta on 03/12/25.
//

import SwiftUI
import YouTubeSDK

#if canImport(TidalKit)
import TidalKit
#endif

#if canImport(SpotifySDK)
import SpotifySDK
#endif

@Observable
@MainActor
class SearchViewModel {

    private enum CachePolicy {
        static let persistentHintMaxAge: TimeInterval = 60 * 60 * 24 * 7
    }

    private let youtube: YouTube
    private let settings: PrefetchSettings
    private let networkMonitor: NetworkPathMonitor
    private let historyStore: SearchHistoryStore?
    private let searchCacheHintStore: SearchCacheHintStore?
    private let streamingProviderSettings: StreamingProviderSettings
    private let metadataCache: any VideoMetadataCaching
    private let searchCache: any SearchResultsCaching

    init(
        youtube: YouTube = .shared,
        settings: PrefetchSettings = .shared,
        networkMonitor: NetworkPathMonitor = .shared,
        historyStore: SearchHistoryStore? = nil,
        searchCacheHintStore: SearchCacheHintStore? = nil,
        streamingProviderSettings: StreamingProviderSettings = .shared,
        metadataCache: any VideoMetadataCaching = VideoMetadataCache.shared,
        searchCache: any SearchResultsCaching = SearchResultsCache.shared
    ) {
        self.youtube = youtube
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.historyStore = historyStore
        self.searchCacheHintStore = searchCacheHintStore
        self.streamingProviderSettings = streamingProviderSettings
        self.metadataCache = metadataCache
        self.searchCache = searchCache
    }

    // Inputs
    var searchText: String = "" {
        didSet { performDebouncedSearch() }
    }
    var searchScope: SearchScope = .video {
        didSet { performDebouncedSearch() }
    }
    
    // Outputs
    var musicResults: [YouTubeMusicSong] = []
    var videoResults: [YouTubeSearchResult] = []
    var federatedSections: [FederatedSearchSection] = FederatedSearchSection.defaultSections
    var suggestions: [String] = []
    var state: SearchState = .idle
    
    // Internal
    private var searchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var lastCompletedQuery: String?
    private var lastCompletedScope: SearchScope?
    private var suggestionCache: [String: [String]] = [:]
    private var lastSuggestionPrefetched: String?
    private var lastHintPrefetchedKey: String?
    private var videoContinuationToken: String?
    private var isLoadingMoreVideos = false
    private var videoContinuationBadResponseCount = 0
    private var lastPaginationTriggerAt: Date?
    private var lastPaginationTriggerToken: String?
    private var inlinePrefetchedVideoIDs: Set<String> = []
    private var inlinePrefetchPendingIDs: Set<String> = []
    private var inlinePrefetchDrainTask: Task<Void, Never>?
    private let inlinePrefetchCoalesceWindow: Duration = .milliseconds(80)
    /// How many items from the end to start prefetching the next page.
    /// Increasing this reduces UI jumps at the cost of earlier network calls.
    private let videoPrefetchThreshold = 10
    private let paginationTriggerCooldown: TimeInterval = 0.25

    var isVideoPaginationLoading: Bool {
        searchScope == .video && isLoadingMoreVideos && !videoResults.isEmpty
    }
    
    enum SearchScope {
        case music
        case video
    }
    
    enum SearchState {
        case idle
        case loading
        case error(String)
        case success
    }
    
    // MARK: - Actions
    
    public func performDebouncedSearch() {
        searchTask?.cancel() // 1. Cancel previous typing
        prefetchTask?.cancel()
        suggestionTask?.cancel()
        inlinePrefetchDrainTask?.cancel()
        inlinePrefetchDrainTask = nil
        inlinePrefetchPendingIDs.removeAll(keepingCapacity: true)
        
        // 2. Clear results if empty
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.musicResults = []
            self.videoResults = []
            self.federatedSections = FederatedSearchSection.defaultSections
            self.suggestions = []
            self.state = .idle
            self.lastHintPrefetchedKey = nil
            self.inlinePrefetchedVideoIDs.removeAll(keepingCapacity: true)
            resetVideoPagination()
            return
        }

        suggestionTask = Task {
            try? await Task.sleep(for: .seconds(0.2))
            if Task.isCancelled { return }
            await fetchSuggestionsForCurrentQuery()
        }
        
        searchTask = Task {
            // 3. Debounce (Wait 0.5s)
            try? await Task.sleep(for: .seconds(0.35))
            if Task.isCancelled { return }

            await executeSearch()
        }
    }
    
    private func executeSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            self.musicResults = []
            self.videoResults = []
            self.federatedSections = FederatedSearchSection.defaultSections
            self.state = .idle
            return
        }

        if case .success = state,
           lastCompletedQuery == query {
            return
        }

        self.state = .loading

        resetFederatedSections(state: .loading)
        historyStore?.recordSearch(query: query)

        let effectiveVideoQuery = effectiveSearchQuery(for: query, scope: .video)

        async let youtubeMusicTask = fetchYouTubeMusicSectionItems(query: query)
        async let youtubeTask = fetchYouTubeSectionItems(query: effectiveVideoQuery)
        async let tidalTask = fetchTidalSectionItems(query: query)
        async let spotifyTask = fetchSpotifySectionItems(query: query)

        let youtubeMusicResult = await youtubeMusicTask
        let youtubeResult = await youtubeTask
        let tidalResult = await tidalTask
        let spotifyResult = await spotifyTask

        applyFederatedSearchResult(youtubeMusicResult, for: .youtubeMusic)
        applyFederatedSearchResult(youtubeResult, for: .youtube)
        applyFederatedSearchResult(tidalResult, for: .tidal)
        applyFederatedSearchResult(spotifyResult, for: .spotify)

        let hasResults = federatedSections.contains { !$0.items.isEmpty }
        if hasResults {
            state = .success
        } else {
            state = .error(firstSectionErrorMessage() ?? "No results found for this search.")
        }

        self.lastCompletedQuery = query
        self.lastCompletedScope = searchScope
    }

    func items(for service: FederatedService) -> [FederatedSearchItem] {
        federatedSections.first(where: { $0.service == service })?.items ?? []
    }

    func sectionState(for service: FederatedService) -> FederatedSectionState {
        federatedSections.first(where: { $0.service == service })?.state ?? .idle
    }

    func resolveExternalStream(for item: FederatedSearchItem) async throws -> ExternalStreamPayload? {
        switch item.payload {
        case .youtubeVideo, .youtubeMusic:
            return nil
        case .tidal(let track):
#if canImport(TidalKit)
            return try await resolveTidalExternalStream(for: track)
#else
            throw FederatedSearchError.providerUnavailable("TidalKit is not linked to this target.")
#endif
        case .spotify(let track):
            guard let previewURL = track.previewURL else {
                throw FederatedSearchError.spotifyPreviewUnavailable
            }

            return ExternalStreamPayload(
                mediaID: "spotify-\(track.id)",
                streamURL: previewURL,
                title: track.title,
                artist: track.artistName,
                artworkURL: track.artworkURL,
                service: .spotify,
                qualityLabel: "Spotify Preview",
                codecLabel: inferCodecLabel(from: previewURL)
            )
        }
    }

    private func resetFederatedSections(state: FederatedSectionState) {
        federatedSections = FederatedSearchSection.defaultSections.map { section in
            var copy = section
            copy.state = state
            copy.items = []
            return copy
        }
    }

    private func applyFederatedSearchResult(
        _ result: Result<[FederatedSearchItem], Error>,
        for service: FederatedService
    ) {
        guard let index = federatedSections.firstIndex(where: { $0.service == service }) else { return }

        switch result {
        case .success(let items):
            federatedSections[index].items = Array(items.prefix(5))
            federatedSections[index].state = .success
        case .failure(let error):
            federatedSections[index].items = []
            federatedSections[index].state = .error(error.localizedDescription)
        }
    }

    private func firstSectionErrorMessage() -> String? {
        for section in federatedSections {
            if case .error(let message) = section.state {
                return message
            }
        }
        return nil
    }

    private func fetchYouTubeMusicSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
        do {
            let results = try await youtube.music.search(query)
            musicResults = results
            searchCache.setMusicResults(results, for: query)
            searchCacheHintStore?.recordMusicResults(query: query, results: results)

            let topResults = Array(results.prefix(5))
            let ids = topResults.map(\.videoId)
            prefetchTopResultIDs(ids)

            let items = topResults.map { song in
                FederatedSearchItem(
                    id: "ytm-\(song.videoId)",
                    title: normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay),
                    subtitle: "\(normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title)) • \(song.album ?? "Single")",
                    artworkURL: song.thumbnailURL,
                    durationSeconds: song.duration,
                    isPlayable: true,
                    payload: .youtubeMusic(song)
                )
            }

            return .success(items)
        } catch {
            return .failure(error)
        }
    }

    private func fetchYouTubeSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
        do {
            let continuation = try await youtube.main.search(query)
            resetVideoPagination()
            updateVideoResults(with: continuation, appending: false)
            searchCache.setVideoResults(videoResults, for: query)
            searchCacheHintStore?.recordVideoResults(query: query, results: videoResults)

            let topVideos = videoResults.compactMap { item -> YouTubeVideo? in
                if case .video(let video) = item {
                    return video
                }
                return nil
            }
            .prefix(5)

            let ids = topVideos.map(\.id)
            prefetchTopResultIDs(ids)

            let items = topVideos.map { video in
                FederatedSearchItem(
                    id: "yt-\(video.id)",
                    title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                    subtitle: normalizedMusicDisplayArtist(video.author, title: video.title),
                    artworkURL: normalizedThumbnailURL(from: video.thumbnailURL),
                    durationSeconds: parseVideoDurationSeconds(video.lengthInSeconds),
                    isPlayable: true,
                    payload: .youtubeVideo(video)
                )
            }

            return .success(Array(items))
        } catch {
            return .failure(error)
        }
    }

    private func fetchTidalSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
#if canImport(TidalKit)
        do {
            let tracks = try await Monochrome.shared.content.searchTracks(query: query)
            let topTracks = Array(tracks.prefix(5)).map { track in
                TidalSearchTrack(
                    id: track.id,
                    title: track.title,
                    artistName: track.artist?.name ?? "Unknown Artist",
                    albumName: track.album?.title,
                    artworkURL: tidalArtworkURL(from: track.album?.cover),
                    durationSeconds: TimeInterval(track.duration),
                    audioQuality: track.audioQuality
                )
            }

            let items = topTracks.map { track in
                FederatedSearchItem(
                    id: "tidal-\(track.id)",
                    title: track.title,
                    subtitle: "\(track.artistName) • \(track.albumName ?? "Tidal")",
                    artworkURL: track.artworkURL,
                    durationSeconds: track.durationSeconds,
                    isPlayable: true,
                    payload: .tidal(track)
                )
            }

            return .success(items)
        } catch {
            return .failure(error)
        }
#else
        return .failure(FederatedSearchError.providerUnavailable("TidalKit is not linked to this target."))
#endif
    }

    private func fetchSpotifySectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
#if canImport(SpotifySDK)
        do {
            let spotify = try makeSpotifyClient()
            let tracksPage = try await spotify.search.tracks(query, limit: 5)
            let topTracks = Array(tracksPage.items.prefix(5)).map { track in
                SpotifySearchTrack(
                    id: track.id,
                    title: track.name,
                    artistName: track.artists.first?.name ?? "Unknown Artist",
                    albumName: track.album?.name,
                    artworkURL: track.album?.images.first?.url,
                    durationSeconds: TimeInterval(track.durationMS) / 1000,
                    previewURL: track.previewURL
                )
            }

            let items = topTracks.map { track in
                FederatedSearchItem(
                    id: "spotify-\(track.id)",
                    title: track.title,
                    subtitle: "\(track.artistName) • \(track.albumName ?? "Spotify")",
                    artworkURL: track.artworkURL,
                    durationSeconds: track.durationSeconds,
                    isPlayable: track.previewURL != nil,
                    payload: .spotify(track)
                )
            }

            return .success(items)
        } catch {
            return .failure(error)
        }
#else
        return .failure(FederatedSearchError.providerUnavailable("SpotifySDK is not linked to this target."))
#endif
    }

    private func parseVideoDurationSeconds(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        return Double(value)
    }

    private func normalizedThumbnailURL(from string: String?) -> URL? {
        guard var candidate = string?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else { return nil }
        if candidate.hasPrefix("//") {
            candidate = "https:" + candidate
        } else if !candidate.hasPrefix("http://") && !candidate.hasPrefix("https://") {
            candidate = "https://" + candidate
        }
        return URL(string: candidate)
    }

    private func inferCodecLabel(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "flac" { return "FLAC" }
        if ext == "m3u8" { return "HLS" }
        if ext == "aac" || ext == "m4a" || ext == "mp4" { return "AAC" }
        if ext == "mp3" { return "MP3" }
        return "Unknown"
    }

#if canImport(TidalKit)
    private func resolveTidalExternalStream(for track: TidalSearchTrack) async throws -> ExternalStreamPayload {
        let preferredQuality = MonochromeAudioQuality(rawValue: streamingProviderSettings.tidalPreferredQualityRawValue) ?? .hiResLossless
        for quality in MonochromeAudioQuality.fallbackOrder(preferred: preferredQuality) {
            guard let urlString = try? await Monochrome.shared.content.fetchStreamURL(trackID: track.id, quality: quality),
                  let streamURL = URL(string: urlString) else {
                continue
            }

            return ExternalStreamPayload(
                mediaID: "tidal-\(track.id)",
                streamURL: streamURL,
                title: track.title,
                artist: track.artistName,
                artworkURL: track.artworkURL,
                service: .tidal,
                qualityLabel: quality.label,
                codecLabel: tidalCodecLabel(for: quality)
            )
        }

        throw FederatedSearchError.noPlayableStream("Unable to resolve a playable Tidal stream for this track.")
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

#if canImport(SpotifySDK)
    private func makeSpotifyClient() throws -> SpotifySDK {
        let clientID = streamingProviderSettings.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = streamingProviderSettings.spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if !clientID.isEmpty, !clientSecret.isEmpty {
            return SpotifySDK(
                official: SpotifyOfficialCredentials(
                    clientID: clientID,
                    clientSecret: clientSecret
                )
            )
        }

        if streamingProviderSettings.spotifyPreferAnonymousFallback {
            return SpotifySDK(publicWebPlayer: .anonymous)
        }

        throw FederatedSearchError.spotifyCredentialsMissing
    }
#endif

    public func applySuggestion(_ suggestion: String) {
        let cleaned = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        searchTask?.cancel()
        searchText = cleaned
        historyStore?.recordSearch(query: cleaned)
        Task { await executeSearch() }
    }

    public func recordSuccessfulPlayFromCurrentQuery() {
        historyStore?.recordSuccessfulPlay(query: searchText)
    }

    // MARK: - Caching Helpers

    private func refreshMusicResultsIfNeeded(for query: String) async {
        await refreshMusicResultsIfNeeded(for: query, scope: searchScope)
    }

    private func refreshMusicResultsIfNeeded(for query: String, scope: SearchScope) async {
        do {
            let effectiveQuery = effectiveSearchQuery(for: query, scope: scope)
            let results = try await youtube.music.search(effectiveQuery)
            searchCache.setMusicResults(results, for: query)
            searchCacheHintStore?.recordMusicResults(query: query, results: results)
            await MainActor.run {
                if self.searchText == query, self.searchScope == scope { self.musicResults = results }
            }
        } catch {
            // ignore background refresh errors
        }
    }

    private func refreshVideoResultsIfNeeded(for query: String) async {
        await refreshVideoResultsIfNeeded(for: query, scope: searchScope)
    }

    private func refreshVideoResultsIfNeeded(for query: String, scope: SearchScope) async {
        do {
            let effectiveQuery = effectiveSearchQuery(for: query, scope: scope)
            let cont = try await youtube.main.search(effectiveQuery)
            let mapped = mapSearchResults(from: cont.items)
            searchCache.setVideoResults(mapped, for: query)
            searchCacheHintStore?.recordVideoResults(query: query, results: mapped)
            await MainActor.run {
                if self.searchText == query, self.searchScope == scope { self.videoResults = mapped }
            }
        } catch {
            // ignore background refresh errors
        }
    }

    // Prefetch metadata and resolved stream urls for top items.
    private func prefetchTopResultIDs(_ ids: [String]) {
        prefetchTask?.cancel()
        guard !ids.isEmpty else { return }
        let youtube = self.youtube
        let mode = effectivePrefetchMode
        let concurrency = currentPrefetchConcurrency
        let metricsEnabled = settings.metricsEnabled
        prefetchTask = Task(priority: .utility) {
            await self.metadataCache.prefetch(
                ids: ids,
                maxConcurrent: concurrency,
                mode: mode,
                metricsEnabled: metricsEnabled
            ) { id in
                try await youtube.main.video(id: id)
            }
        }
    }

    // Public helper to prefetch a single id (used by row onAppear)
    public func prefetchIfNeeded(id: String) {
        guard !id.isEmpty else { return }
        guard inlinePrefetchedVideoIDs.insert(id).inserted else { return }
        inlinePrefetchPendingIDs.insert(id)
        scheduleInlinePrefetchDrainIfNeeded()
    }

    private func scheduleInlinePrefetchDrainIfNeeded() {
        guard inlinePrefetchDrainTask == nil else { return }

        let youtube = self.youtube
        let mode = effectivePrefetchMode
        let metricsEnabled = settings.metricsEnabled
        let concurrency = max(1, min(2, currentPrefetchConcurrency))

        inlinePrefetchDrainTask = Task(priority: .utility) {
            try? await Task.sleep(for: inlinePrefetchCoalesceWindow)
            if Task.isCancelled {
                inlinePrefetchDrainTask = nil
                return
            }

            let ids = Array(inlinePrefetchPendingIDs)
            inlinePrefetchPendingIDs.removeAll(keepingCapacity: true)
            guard !ids.isEmpty else {
                inlinePrefetchDrainTask = nil
                return
            }

            await self.metadataCache.prefetch(
                ids: ids,
                maxConcurrent: concurrency,
                mode: mode,
                metricsEnabled: metricsEnabled
            ) { key in
                try await youtube.main.video(id: key)
            }

            inlinePrefetchDrainTask = nil
            if !inlinePrefetchPendingIDs.isEmpty {
                scheduleInlinePrefetchDrainIfNeeded()
            }
        }
    }

    private func fetchSuggestionsForCurrentQuery() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestions = []
            return
        }

        let cacheKey = "\(searchScope)-\(query.lowercased())"
        if let cached = suggestionCache[cacheKey] {
            suggestions = cached
            if settings.suggestionPipelineEnabled {
                await prefetchFromTopSuggestionIfNeeded(cached)
            }
            return
        }

        do {
            let remote: [String]
            switch searchScope {
            case .music:
                remote = try await youtube.music.getSearchSuggestions(query: query)
            case .video:
                remote = try await youtube.main.getSearchSuggestions(query: effectiveSearchQuery(for: query, scope: .video))
            }

            let local = historyStore?.topCandidates(prefix: query, limit: 20) ?? []
            var candidates: [SuggestionCandidate] = []

            candidates.append(contentsOf: remote.map {
                SuggestionCandidate(
                    text: $0,
                    frequency: 0,
                    successfulPlays: 0,
                    recency: .distantPast,
                    sourceBoost: 0.6
                )
            })

            candidates.append(contentsOf: local.map {
                SuggestionCandidate(
                    text: $0.query,
                    frequency: $0.searchCount,
                    successfulPlays: $0.successfulPlayCount,
                    recency: $0.lastSearchedAt,
                    sourceBoost: 1.0
                )
            })

            let ranked = SuggestionRanker.rank(input: query, candidates: candidates, limit: 8)
            suggestionCache[cacheKey] = ranked
            suggestions = ranked

            if settings.suggestionPipelineEnabled {
                await prefetchFromTopSuggestionIfNeeded(ranked)
            }
        } catch {
            // Keep UI responsive even if suggestions endpoint fails.
            suggestions = (historyStore?.topCandidates(prefix: query, limit: 8) ?? []).map { $0.query }
        }
    }

    private func prefetchFromTopSuggestionIfNeeded(_ rankedSuggestions: [String]) async {
        guard let top = rankedSuggestions.first else { return }
        guard top != lastSuggestionPrefetched else { return }
        lastSuggestionPrefetched = top

        let normalizedTop = top.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTop.isEmpty else { return }

        let scope = searchScope
        let mode = effectivePrefetchMode
        let metricsEnabled = settings.metricsEnabled
        let youtube = self.youtube

        do {
            let ids: [String]
            switch scope {
            case .music:
                let results: [YouTubeMusicSong]
                if let cached = searchCache.getMusicResults(for: normalizedTop), !cached.isStale {
                    results = cached.results
                } else {
                    results = try await youtube.music.search(effectiveSearchQuery(for: normalizedTop, scope: scope))
                    searchCache.setMusicResults(results, for: normalizedTop)
                    searchCacheHintStore?.recordMusicResults(query: normalizedTop, results: results)
                }
                ids = Array(results.prefix(3).map { $0.videoId })

            case .video:
                let results: [YouTubeSearchResult]
                if let cached = searchCache.getVideoResults(for: normalizedTop), !cached.isStale {
                    results = cached.results
                } else {
                    let continuation = try await youtube.main.search(effectiveSearchQuery(for: normalizedTop, scope: scope))
                    let mapped = mapSearchResults(from: continuation.items)
                    searchCache.setVideoResults(mapped, for: normalizedTop)
                    searchCacheHintStore?.recordVideoResults(query: normalizedTop, results: mapped)
                    results = mapped
                }
                ids = Array(results.compactMap { item -> String? in
                    if case .video(let v) = item { return v.id }
                    return nil
                }.prefix(3))
            }

            await metadataCache.prefetch(
                ids: ids,
                maxConcurrent: min(3, currentPrefetchConcurrency),
                mode: mode,
                metricsEnabled: metricsEnabled
            ) { id in
                try await youtube.main.video(id: id)
            }
        } catch {
            // Best effort prefetch.
        }
    }

    private var currentPrefetchCount: Int {
        guard settings.adaptivePrefetchEnabled else {
            return max(1, settings.wifiPrefetchCount)
        }
        if networkMonitor.interface == .cellular || networkMonitor.isExpensive || networkMonitor.isConstrained {
            return max(1, settings.cellularPrefetchCount)
        }
        return max(1, settings.wifiPrefetchCount)
    }

    private var currentPrefetchConcurrency: Int {
        guard settings.adaptivePrefetchEnabled else {
            return max(1, settings.wifiPrefetchConcurrency)
        }
        if networkMonitor.interface == .cellular || networkMonitor.isExpensive || networkMonitor.isConstrained {
            return max(1, settings.cellularPrefetchConcurrency)
        }
        return max(1, settings.wifiPrefetchConcurrency)
    }

    private var effectivePrefetchMode: PrefetchModeOverride {
        if settings.prefetchModeOverride != .auto {
            return settings.prefetchModeOverride
        }
        if networkMonitor.interface == .wifi, !networkMonitor.isExpensive, !networkMonitor.isConstrained {
            return .aggressiveWarmup
        }
        return .metadataOnly
    }

    private func prefetchFromPersistentHintsIfNeeded(for query: String) {
        guard let searchCacheHintStore else { return }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        let key = "\(searchScope)-\(normalized)"
        guard key != lastHintPrefetchedKey else { return }

        let scope: SearchCacheHintStore.Scope = {
            switch searchScope {
            case .music: return .music
            case .video: return .video
            }
        }()

        let ids = searchCacheHintStore.cachedTopVideoIDs(
            for: normalized,
            scope: scope,
            maxAge: CachePolicy.persistentHintMaxAge
        )
        guard !ids.isEmpty else { return }

        lastHintPrefetchedKey = key

        let youtube = self.youtube
        let mode = effectivePrefetchMode
        let metricsEnabled = settings.metricsEnabled
        let concurrency = min(4, currentPrefetchConcurrency)

        Task(priority: .utility) {
            await self.metadataCache.prefetch(
                ids: Array(ids.prefix(6)),
                maxConcurrent: concurrency,
                mode: mode,
                metricsEnabled: metricsEnabled
            ) { id in
                try await youtube.main.video(id: id)
            }
        }
    }

    func loadMoreVideosIfNeeded(for item: YouTubeSearchResult) {
        guard searchScope == .video else { return }
        // Trigger when the appearing item is within `videoPrefetchThreshold`
        // items from the end so we begin loading earlier and reduce jumps.
        guard let idx = videoResults.firstIndex(where: { $0.id == item.id }) else { return }
        let shouldTrigger = idx >= (videoResults.count - videoPrefetchThreshold)
        guard shouldTrigger else { return }
        guard let token = videoContinuationToken, !token.isEmpty else { return }
        guard !isLoadingMoreVideos else { return }

        if let lastTime = lastPaginationTriggerAt,
           lastPaginationTriggerToken == token,
           Date().timeIntervalSince(lastTime) < paginationTriggerCooldown {
            return
        }

        lastPaginationTriggerAt = Date()
        lastPaginationTriggerToken = token

        Task {
            await loadMoreVideos()
        }
    }

    private func loadMoreVideos() async {
        guard let token = videoContinuationToken, !token.isEmpty else { return }
        guard !isLoadingMoreVideos else { return }

        isLoadingMoreVideos = true
        defer { isLoadingMoreVideos = false }

        do {
            let continuation = try await youtube.main.fetchContinuation(token: token)
            updateVideoResults(with: continuation, appending: true)
            // Reset bad-response counter on successful continuation
            videoContinuationBadResponseCount = 0
        } catch {
            if !Task.isCancelled {
                // If the error looks like a repeated bad server response (HTTP 400
                // or NSURLErrorBadServerResponse -1011), increment a counter and
                // defensively clear the continuation token after a couple attempts
                // to avoid spamming failing requests while the user scrolls.
                if let ns = error as NSError? {
                    if ns.code == 400 || (ns.domain == NSURLErrorDomain && ns.code == -1011) {
                        videoContinuationBadResponseCount += 1
                        if videoContinuationBadResponseCount >= 2 {
                            videoContinuationToken = nil
                            state = .error("Pagination temporarily disabled due to server responses.")
                        }
                    } else {
                        videoContinuationBadResponseCount = 0
                    }
                } else {
                    videoContinuationBadResponseCount = 0
                }
            }
        }
    }

    private func updateVideoResults(with continuation: YouTubeContinuation<YouTubeItem>, appending: Bool) {
        let mapped = mapSearchResults(from: continuation.items)
        if appending {
            self.videoResults.append(contentsOf: mapped)
        } else {
            // Initial load replace without animation to avoid strange layout jumps.
            self.videoResults = mapped
        }

        self.videoContinuationToken = continuation.continuationToken
        // Re-arm trigger protection for the next token progression.
        self.lastPaginationTriggerToken = continuation.continuationToken
        // Successful parse/append — reset any bad-response tracking
        videoContinuationBadResponseCount = 0
    }

    private func mapSearchResults(from items: [YouTubeItem]) -> [YouTubeSearchResult] {
        return items.compactMap { item in
            switch item {
            case .video(let v):
                guard shouldKeepVideoResult(v) else { return nil }
                return .video(v)
            case .channel(let c):
                guard shouldKeepMusicChannel(c) else { return nil }
                return .channel(c)
            case .playlist(let p):
                guard shouldKeepMusicPlaylist(p) else { return nil }
                return .playlist(p)
            default: return nil
            }
        }
    }

    private func effectiveSearchQuery(for query: String, scope: SearchScope) -> String {
        switch scope {
        case .music:
            return query
        case .video:
            return musicVideoSearchQuery(query)
        }
    }

    private func shouldKeepVideoResult(_ video: YouTubeVideo) -> Bool {
        shouldKeepMusicVideoResult(video)
    }

    private func resetVideoPagination() {
        videoContinuationToken = nil
        isLoadingMoreVideos = false
        videoContinuationBadResponseCount = 0
        lastPaginationTriggerAt = nil
        lastPaginationTriggerToken = nil
    }
}

enum FederatedService: String, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case youtubeMusic = "YouTube Music"
    case tidal = "Tidal"
    case spotify = "Spotify"

    var id: FederatedService { self }
}

enum FederatedSectionState: Equatable {
    case idle
    case loading
    case success
    case error(String)
}

struct FederatedSearchSection: Identifiable {
    let service: FederatedService
    var state: FederatedSectionState
    var items: [FederatedSearchItem]

    var id: FederatedService { service }

    static var defaultSections: [FederatedSearchSection] {
        FederatedService.allCases.map {
            FederatedSearchSection(service: $0, state: .idle, items: [])
        }
    }
}

struct TidalSearchTrack: Identifiable {
    let id: Int
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let durationSeconds: TimeInterval
    let audioQuality: String?
}

struct SpotifySearchTrack: Identifiable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let durationSeconds: TimeInterval
    let previewURL: URL?
}

enum FederatedSearchPayload {
    case youtubeVideo(YouTubeVideo)
    case youtubeMusic(YouTubeMusicSong)
    case tidal(TidalSearchTrack)
    case spotify(SpotifySearchTrack)
}

struct FederatedSearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let durationSeconds: TimeInterval?
    let isPlayable: Bool
    let payload: FederatedSearchPayload
}

struct ExternalStreamPayload {
    let mediaID: String
    let streamURL: URL
    let title: String
    let artist: String
    let artworkURL: URL?
    let service: FederatedService
    let qualityLabel: String
    let codecLabel: String
}

enum FederatedSearchError: LocalizedError {
    case providerUnavailable(String)
    case spotifyCredentialsMissing
    case spotifyPreviewUnavailable
    case noPlayableStream(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let message):
            return message
        case .spotifyCredentialsMissing:
            return "Spotify credentials are missing. Add a Client ID and Client Secret in Settings."
        case .spotifyPreviewUnavailable:
            return "Spotify track playback is unavailable for this item (no preview URL)."
        case .noPlayableStream(let message):
            return message
        }
    }
}
