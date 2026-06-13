import Caching
import Library
import Models
import Networking
import Observation
import Player
import Plugins
import ProviderSDK
import Search
import SwiftUI
import Utilities
import YouTubeSDK
#if canImport(SpotifySDK)
import SpotifySDK
#endif

@Observable
@MainActor
public class SearchViewModel: SearchViewModelInterface {
    private enum CachePolicy {
        nonisolated static let persistentHintMaxAge: TimeInterval = 60 * 60 * 24 * 7
    }

    private enum UnifiedTopResultsPolicy {
        nonisolated static let limit: Int = 10
        // All four service types participate in unified top results
        nonisolated static let services: [FederatedService] = [.spotify, .youtubeMusic, .youtube, .providerSDK]
        nonisolated static let maxPerService: [FederatedService: Int] = [
            .spotify: 5,
            .youtubeMusic: 3,
            .youtube: 3,
            .providerSDK: 8, // Up to 8 streaming-provider tracks (SoundCloud, Tidal, Qobuz…)
        ]
    }

    private enum YouMightLikePolicy {
        nonisolated static let limit: Int = 8
        nonisolated static let services: [FederatedService] = [.spotify, .providerSDK, .youtubeMusic, .youtube]
    }

    /// Fallback resolution order for Spotify items: YouTube Music → YouTube
    private enum SpotifyFallbackResolutionPolicy {
        nonisolated static let order: [FederatedService] = [.youtubeMusic, .youtube]
    }

    private let youtube: YouTube
    private let providerSDK: ProviderSDK?
    private let settings: PrefetchSettings
    private let networkMonitor: NetworkPathMonitor
    private let historyStore: SearchHistoryStore
    private let searchCacheHintStore: SearchCacheHintStore
    private let streamingProviderSettings: StreamingProviderSettings
    private let centralMediaStore: CentralMediaStore?
    private let metadataCache: any VideoMetadataCaching
    private let searchCache: any SearchResultsCaching

    public init(
        youtube: YouTube,
        settings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor,
        historyStore: SearchHistoryStore,
        searchCacheHintStore: SearchCacheHintStore,
        streamingProviderSettings: StreamingProviderSettings,
        centralMediaStore: CentralMediaStore? = nil,
        metadataCache: any VideoMetadataCaching,
        searchCache: any SearchResultsCaching,
        providerSDK: ProviderSDK? = nil
    ) {
        self.youtube = youtube
        self.providerSDK = providerSDK
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.historyStore = historyStore
        self.searchCacheHintStore = searchCacheHintStore
        self.streamingProviderSettings = streamingProviderSettings
        self.centralMediaStore = centralMediaStore
        self.metadataCache = metadataCache
        self.searchCache = searchCache
    }

    /// Inputs
    public var searchText: String = "" {
        didSet { performDebouncedSearch() }
    }

    public var searchScope: Models.SearchScope = .video {
        didSet { performDebouncedSearch() }
    }

    // Outputs
    public var musicResults: [YouTubeMusicSong] = []
    public var videoResults: [YouTubeSearchResult] = []
    public var federatedSections: [FederatedSearchSection] = FederatedSearchSection.defaultSections
    public var unifiedTopResults: [FederatedSearchItem] = []
    public var youMightLikeResults: [FederatedSearchItem] = []
    public var suggestions: [String] = []
    public var recentSearches: [String] = []
    public var state: SearchState = .idle

    // Spotify visible sections
    public var spotifyTrackResults: [FederatedSearchItem] = []
    public var spotifyArtistResults: [FederatedSearchItem] = []
    public var spotifyPlaylistResults: [FederatedSearchItem] = []

    /// Maps spotify item ID → best matching hidden-provider item
    /// Populated asynchronously after hidden providers complete.
    public private(set) var hiddenFallbackMap: [String: FederatedSearchItem] = [:]

    // Internal
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var lastCompletedQuery: String?
    @ObservationIgnored private var suggestionCache: [String: [String]] = [:]
    @ObservationIgnored private var lastSuggestionPrefetched: String?
    @ObservationIgnored private var lastHintPrefetchedKey: String?
    @ObservationIgnored private var videoContinuationToken: String?
    @ObservationIgnored private var isLoadingMoreVideos = false
    @ObservationIgnored private var videoContinuationBadResponseCount = 0
    @ObservationIgnored private var lastPaginationTriggerAt: Date?
    @ObservationIgnored private var lastPaginationTriggerToken: String?
    @ObservationIgnored private var inlinePrefetchedVideoIDs: Set<String> = []
    @ObservationIgnored private var inlinePrefetchPendingIDs: Set<String> = []
    @ObservationIgnored private var inlinePrefetchDrainTask: Task<Void, Never>?
    @ObservationIgnored private let inlinePrefetchCoalesceWindow: Duration = .milliseconds(80)
    /// How many items from the end to start prefetching the next page.
    /// Increasing this reduces UI jumps at the cost of earlier network calls.
    @ObservationIgnored private let videoPrefetchThreshold = 10
    @ObservationIgnored private let paginationTriggerCooldown: TimeInterval = 0.25

    public var isVideoPaginationLoading: Bool {
        searchScope == .video && isLoadingMoreVideos && !videoResults.isEmpty
    }

    // MARK: - Actions

    public func performDebouncedSearch() {
        PerfLog.trace("SearchViewModel: performDebouncedSearch called with text: '\(searchText)'")
        searchTask?.cancel() // 1. Cancel previous typing
        prefetchTask?.cancel()
        suggestionTask?.cancel()
        inlinePrefetchDrainTask?.cancel()
        inlinePrefetchDrainTask = nil
        inlinePrefetchPendingIDs.removeAll(keepingCapacity: true)

        // 2. Clear results if empty
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            PerfLog.trace("SearchViewModel: Text is empty, clearing results.")
            clearAllResults()
            suggestions = []
            state = .idle
            return
        }

        suggestionTask = Task {
            try? await Task.sleep(for: .seconds(0.4))
            if Task.isCancelled { return }
            await fetchSuggestionsForCurrentQuery()
        }

        searchTask = Task {
            // 3. Debounce (Wait 0.5s)
            try? await Task.sleep(for: .seconds(0.6))
            if Task.isCancelled { return }

            PerfLog.info("SearchViewModel: Debounce finished, executing search for '\(searchText)'")
            await executeSearch()
        }
    }

    private func executeSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            clearAllResults()
            state = .idle
            return
        }

        if case .success = state,
           lastCompletedQuery == query
        {
            PerfLog.info("SearchViewModel: Query '\(query)' matches last completed query, skipping.")
            return
        }

        PerfLog.info("SearchViewModel: Starting parallel unified search for '\(query)'")
        state = .loading

        resetFederatedSections(state: .loading)
        clearSpotifySections()
        unifiedTopResults = []
        youMightLikeResults = []
        hiddenFallbackMap = [:]
        await historyStore.recordSearch(query: query)

        let effectiveVideoQuery = effectiveSearchQuery(for: query, scope: Models.SearchScope.video)

        // M-8 fix: run all four provider queries concurrently so total latency is
        // max(individual) instead of sum(individual). Each async let fires immediately.
        async let spotifyFetch = fetchSpotifySectionItems(query: query)
        async let ytMusicFetch = fetchYouTubeMusicSectionItems(query: query, updateUI: true)
        async let ytVideoFetch = fetchYouTubeSectionItems(query: effectiveVideoQuery, updateUI: true)
        async let providerFetch = fetchProviderSDKSectionItems(query: query)

        let (spotifyResult, ytMusicResult, ytVideoResult, providerResult) =
            await (spotifyFetch, ytMusicFetch, ytVideoFetch, providerFetch)

        try? Task.checkCancellation()

        applySpotifySearchResult(spotifyResult)
        applyFederatedSearchResult(ytMusicResult, for: .youtubeMusic)
        applyFederatedSearchResult(ytVideoResult, for: .youtube)
        applyFederatedSearchResult(providerResult, for: .providerSDK)
        refreshUnifiedResults(for: query)

        state = .success
        lastCompletedQuery = query
        triggerHapticFeedback()
    }

    public func triggerHapticFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func refreshUnifiedResults(for query: String) {
        buildHiddenFallbackMap(for: query)

        let sections = federatedSections
        let currentSpotifyTrackResults = spotifyTrackResults
        let currentSpotifyArtistResults = spotifyArtistResults
        let currentSpotifyPlaylistResults = spotifyPlaylistResults

        Task {
            let topResults = await self.performUnifiedRanking(for: query, sections: sections)
            let excludedIDs = Set(topResults.map(\.id))
            let likeResults = await self.performYouMightLikeRanking(for: query, sections: sections, anchorResults: topResults, excludingIDs: excludedIDs)

            await MainActor.run {
                // Verify query still matches to avoid stale results
                guard query == self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                self.unifiedTopResults = topResults
                self.youMightLikeResults = likeResults

                let hasResults = !currentSpotifyTrackResults.isEmpty
                    || !currentSpotifyArtistResults.isEmpty
                    || !currentSpotifyPlaylistResults.isEmpty
                    || !topResults.isEmpty
                    || !likeResults.isEmpty

                if hasResults, self.state == .loading {
                    self.state = .success
                }
            }
        }
    }

    private nonisolated func performUnifiedRanking(for query: String, sections: [FederatedSearchSection]) async -> [FederatedSearchItem] {
        buildUnifiedTopResults(for: query, in: sections)
    }

    private nonisolated func performYouMightLikeRanking(for query: String, sections: [FederatedSearchSection], anchorResults: [FederatedSearchItem], excludingIDs: Set<String>) async -> [FederatedSearchItem] {
        buildYouMightLikeResults(for: query, in: sections, anchorResults: anchorResults, excludingIDs: excludingIDs)
    }

    private func clearAllResults() {
        musicResults = []
        videoResults = []
        federatedSections = FederatedSearchSection.defaultSections
        unifiedTopResults = []
        youMightLikeResults = []
        clearSpotifySections()
        hiddenFallbackMap = [:]
        lastHintPrefetchedKey = nil
        inlinePrefetchedVideoIDs.removeAll(keepingCapacity: true)
        resetVideoPagination()
        loadRecentSearches()
    }

    public func loadRecentSearches() {
        Task {
            // Fetch up to 15 top searches with empty prefix (meaning all history)
            let searches = await historyStore.topCandidates(prefix: "", limit: 15).map(\.query)
            await MainActor.run {
                self.recentSearches = searches
            }
        }
    }

    public func removeRecentSearch(_ query: String) {
        Task {
            await historyStore.removeSearch(query: query)
            loadRecentSearches()
        }
    }

    private func clearSpotifySections() {
        spotifyTrackResults = []
        spotifyArtistResults = []
        spotifyPlaylistResults = []
    }

    private func applySpotifySearchResult(_ result: Result<SpotifySearchItems, Error>) {
        switch result {
        case let .success(items):
            spotifyTrackResults = items.tracks
            spotifyArtistResults = items.artists
            spotifyPlaylistResults = items.playlists

            // Unify Spotify tracks into federatedSections for Unified Ranking
            if let index = federatedSections.firstIndex(where: { $0.service == .spotify }) {
                federatedSections[index].items = Array(items.tracks.prefix(5))
                federatedSections[index].state = .success
            }
        case .failure:
            clearSpotifySections()
            if let index = federatedSections.firstIndex(where: { $0.service == .spotify }) {
                federatedSections[index].items = []
                federatedSections[index].state = .error("Failed to load Spotify")
            }
        }
    }

    /// Builds a map of spotifyItemID → best hidden-provider match by title+artist similarity.
    private func buildHiddenFallbackMap(for query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let hiddenItems = SpotifyFallbackResolutionPolicy.order.flatMap { items(for: $0) }
        guard !hiddenItems.isEmpty else { return }

        for spotifyItem in spotifyTrackResults {
            let spotifyTitle = normalizedRankingText(spotifyItem.title)
            let spotifyArtist = normalizedRankingText(primaryArtistName(from: spotifyItem.subtitle))

            let bestMatch = hiddenItems
                .filter(\.isPlayable)
                .map { hiddenItem -> (item: FederatedSearchItem, score: Double) in
                    let hiddenTitle = normalizedRankingText(hiddenItem.title)
                    let hiddenArtist = normalizedRankingText(primaryArtistName(from: hiddenItem.subtitle))
                    let titleSim = tokenOverlapScore(spotifyTitle, hiddenTitle)
                    let artistSim = tokenOverlapScore(spotifyArtist, hiddenArtist)
                    let priority = providerPriority(for: hiddenItem.service)
                    let serviceBonus = Double(3 - priority) * 0.02
                    return (hiddenItem, (0.6 * titleSim) + (0.4 * artistSim) + serviceBonus)
                }
                .filter { $0.score > 0.4 }
                .max(by: { $0.score < $1.score })
                .map(\.item)

            if let match = bestMatch {
                hiddenFallbackMap[spotifyItem.id] = match
            }
        }
    }

    public func items(for service: FederatedService) -> [FederatedSearchItem] {
        federatedSections.first(where: { $0.service == service })?.items ?? []
    }

    public func sectionState(for service: FederatedService) -> FederatedSectionState {
        federatedSections.first(where: { $0.service == service })?.state ?? .idle
    }

    public func resolveExternalStream(for item: FederatedSearchItem) async throws -> ExternalStreamPayload? {
        try await resolveExternalStream(for: item, spotifyItem: nil)
    }

    public func resolveExternalStream(for item: FederatedSearchItem, spotifyItem: FederatedSearchItem?) async throws -> ExternalStreamPayload? {
        switch item.payload {
        case let .youtubeVideo(video):
            try await resolveYouTubeExternalStream(
                for: video.id,
                title: video.title,
                artist: video.author,
                artworkURL: video.thumbnailURL.flatMap { URL(string: $0) },
                service: .youtube,
                spotifyItem: spotifyItem
            )

        case let .youtubeMusic(song):
            try await resolveYouTubeExternalStream(
                for: song.videoId,
                title: song.title,
                artist: song.artists.first ?? "Unknown",
                artworkURL: song.thumbnailURL,
                service: .youtubeMusic,
                spotifyItem: spotifyItem
            )

        case .spotify:
            try await resolveSpotifyViaHiddenFallback(for: item)

        case .spotifyArtist, .spotifyPlaylist:
            nil

        case let .providerSDKTrack(track):
            try await resolveProviderSDKExternalStream(for: track, fallbackSpotifyItem: spotifyItem)
        }
    }

    private func resolveYouTubeExternalStream(for videoID: String, title: String, artist: String, artworkURL: URL?, service: FederatedService, spotifyItem: FederatedSearchItem? = nil) async throws -> ExternalStreamPayload {
        var representations: [TrackRepresentation] = []
        let ytRep = TrackRepresentation(
            providerID: service == .youtubeMusic ? "youtubeMusic" : "youtube",
            providerTrackID: videoID,
            title: title,
            artist: artist,
            artworkURL: artworkURL
        )
        representations.append(ytRep)

        if let spotifyItem, let spotifyID = spotifyTrackID(from: spotifyItem) {
            var isrc: String?
            if case let .spotify(track) = spotifyItem.payload {
                isrc = track.isrc
            }

            let spotifyRep = TrackRepresentation(
                providerID: "spotify",
                providerTrackID: spotifyID,
                title: spotifyItem.title,
                artist: primaryArtistName(from: spotifyItem.subtitle),
                duration: spotifyItem.durationSeconds,
                isrc: isrc,
                artworkURL: spotifyItem.artworkURL
            )
            representations.append(spotifyRep)
        }

        let resolver = await PlaybackURLResolver.sharedInstance()
        let candidates = try await resolver.resolve(mediaID: videoID, title: title, artist: artist, representations: representations, forceDecipher: false, duration: spotifyItem?.durationSeconds)
        guard let url = candidates.first?.url else {
            throw NSError(domain: "SearchViewModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "No playback stream found"])
        }

        let ext = url.pathExtension.lowercased()
        let codec = ext == "m3u8" ? "hls" : "mp4"
        let quality = codec == "hls" ? "Adaptive" : "Standard"
        return ExternalStreamPayload(
            mediaID: videoID,
            streamURL: url,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            service: .youtube,
            qualityLabel: quality,
            codecLabel: codec
        )
    }

    /// Resolves a playable stream for a Spotify item by matching against hidden providers.
    /// Resolution order: YouTube Music → YouTube.
    private func resolveSpotifyViaHiddenFallback(for spotifyItem: FederatedSearchItem) async throws -> ExternalStreamPayload? {
        var activeSpotifyItem = spotifyItem

        // 0. Check CentralMediaStore for a cached provider ID
        if let centralMediaStore,
           let spotifyID = spotifyTrackID(from: activeSpotifyItem)
        {
            let cachedIDs = await centralMediaStore.cachedProviderIDs(forSpotifyTrackID: spotifyID)

            if let ytMusicID = cachedIDs?.youtubeMusicVideoID {
                return try await resolveYouTubeExternalStream(
                    for: ytMusicID,
                    title: activeSpotifyItem.title,
                    artist: primaryArtistName(from: activeSpotifyItem.subtitle),
                    artworkURL: activeSpotifyItem.artworkURL,
                    service: .youtubeMusic,
                    spotifyItem: activeSpotifyItem
                )
            } else if let ytID = cachedIDs?.youtubeVideoID {
                return try await resolveYouTubeExternalStream(
                    for: ytID,
                    title: activeSpotifyItem.title,
                    artist: primaryArtistName(from: activeSpotifyItem.subtitle),
                    artworkURL: activeSpotifyItem.artworkURL,
                    service: .youtube,
                    spotifyItem: activeSpotifyItem
                )
            }
            // Add other providers (tidal, qobuz) later if ProviderSDK resolution supports it directly here.
        }

        // 1. Ensure we have the ISRC for accurate matching
        if case let .spotify(track) = activeSpotifyItem.payload, track.isrc == nil {
            if let fullTrack = await fetchFullSpotifyTrack(id: track.id) {
                let updatedTrack = SpotifySearchTrack(
                    id: track.id,
                    title: fullTrack.name,
                    artistName: track.artistName,
                    albumName: track.albumName,
                    artworkURL: track.artworkURL,
                    durationSeconds: track.durationSeconds,
                    previewURL: track.previewURL,
                    isrc: fullTrack.externalIDs?["isrc"]
                )

                activeSpotifyItem = FederatedSearchItem(
                    id: activeSpotifyItem.id,
                    title: activeSpotifyItem.title,
                    subtitle: activeSpotifyItem.subtitle,
                    artworkURL: activeSpotifyItem.artworkURL,
                    durationSeconds: activeSpotifyItem.durationSeconds,
                    isPlayable: activeSpotifyItem.isPlayable,
                    isExplicit: activeSpotifyItem.isExplicit,
                    audioQualityLabel: activeSpotifyItem.audioQualityLabel,
                    audioCodecLabel: activeSpotifyItem.audioCodecLabel,
                    payload: .spotify(updatedTrack)
                )

                PerfLog.info("SearchViewModel: Hydrated Spotify track with ISRC: \(updatedTrack.isrc ?? "none")")
            }
        }

        let spotifyTitle = activeSpotifyItem.title
        let spotifyArtist = primaryArtistName(from: activeSpotifyItem.subtitle)
        let spotifyDuration = activeSpotifyItem.durationSeconds
        let spotifyISRC: String? = {
            if case let .spotify(track) = activeSpotifyItem.payload { return track.isrc }
            return nil
        }()

        // Try local visible results next (fast path)
        let hiddenItems = SpotifyFallbackResolutionPolicy.order.flatMap { items(for: $0) }

        // Use a structured task (not detached) so actor isolation is preserved
        let bestLocal: SpotifyFallbackMatch? = await Task { [weak self] in
            guard let self else { return nil }
            return findBestSpotifyFallbackMatch(
                for: spotifyTitle,
                artist: spotifyArtist,
                durationSeconds: spotifyDuration,
                sourceISRC: spotifyISRC,
                in: hiddenItems
            )
        }.value

        if let bestLocal, bestLocal.score >= 0.72 {
            if let payload = try await resolveExternalStream(for: bestLocal.item, spotifyItem: activeSpotifyItem) {
                rememberSpotifyPlaybackTarget(for: activeSpotifyItem, payload: payload)
                return payload
            }
        }

        // 3. Try on-demand search (slow path)
        if let onDemandFallback = await resolveSpotifyOnDemandYouTubeFallback(
            spotifyItem: activeSpotifyItem,
            title: spotifyTitle,
            artist: spotifyArtist,
            durationSeconds: spotifyDuration,
            artworkURL: activeSpotifyItem.artworkURL
        ) {
            rememberSpotifyPlaybackTarget(for: activeSpotifyItem, payload: onDemandFallback)
            return onDemandFallback
        }

        throw FederatedSearchError.noPlayableStream(
            "No YouTube-backed stream could be found for \"\(spotifyTitle)\"."
        )
    }

    private func fetchFullSpotifyTrack(id: String) async -> SpotifyTrack? {
        #if canImport(SpotifySDK)
        do {
            let spotify = try await makeSpotifyClient()
            return try await spotify.restClient.fetchTrack(id: id)
        } catch {
            PerfLog.info("SearchViewModel: Failed to fetch full Spotify track: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private func rememberSpotifyPlaybackTarget(for spotifyItem: FederatedSearchItem, payload: ExternalStreamPayload) {
        guard let spotifyTrackID = spotifyTrackID(from: spotifyItem) else { return }
        guard let canonicalProvider = canonicalProvider(for: payload.service) else { return }

        Task {
            await centralMediaStore?.cacheSpotifyPlaybackTarget(
                spotifyTrackID: spotifyTrackID,
                mediaID: payload.mediaID,
                provider: canonicalProvider
            )
        }
    }

    private func spotifyTrackID(from item: FederatedSearchItem) -> String? {
        guard item.id.hasPrefix("spotify-") else { return nil }
        return String(item.id.dropFirst("spotify-".count))
    }

    private func canonicalProvider(for service: FederatedService) -> MediaProvider? {
        switch service {
        case .youtube:
            .youtube
        case .youtubeMusic:
            .youtubeMusic
        case .spotify:
            .spotify
        case .providerSDK:
            nil // ProviderSDK may resolve via multiple providers; no single canonical mapping.
        }
    }

    private func resolveSpotifyOnDemandYouTubeFallback(
        spotifyItem: FederatedSearchItem,
        title: String,
        artist: String,
        durationSeconds: TimeInterval?,
        artworkURL _: URL?
    ) async -> ExternalStreamPayload? {
        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistValue = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        let query = [artistValue, titleValue].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }

        // Extract source ISRC for exact-match scoring
        let sourceISRC: String? = {
            if case let .spotify(track) = spotifyItem.payload { return track.isrc }
            return nil
        }()

        PerfLog.info("SearchViewModel: Resolving Spotify fallback in parallel for '\(query)'...")

        return await withTaskGroup(of: ExternalStreamPayload?.self) { group in
            // 1. YouTube Music Task
            group.addTask {
                guard !Task.isCancelled else { return nil }
                let result = await self.fetchYouTubeMusicSectionItems(query: query, updateUI: false)
                if case let .success(items) = result {
                    if let best = await self.performFallbackMatch(title: titleValue, artist: artistValue, duration: durationSeconds, sourceISRC: sourceISRC, candidates: items) {
                        return try? await self.resolveExternalStream(for: best.item, spotifyItem: spotifyItem)
                    }
                }
                return nil
            }

            // 2. YouTube Video Task
            group.addTask {
                guard !Task.isCancelled else { return nil }
                let videoQuery = self.effectiveSearchQuery(for: query, scope: Models.SearchScope.video)
                let result = await self.fetchYouTubeSectionItems(query: videoQuery, updateUI: false)
                if case let .success(items) = result {
                    if let best = await self.performFallbackMatch(title: titleValue, artist: artistValue, duration: durationSeconds, sourceISRC: sourceISRC, candidates: items) {
                        return try? await self.resolveExternalStream(for: best.item, spotifyItem: spotifyItem)
                    }
                }
                return nil
            }

            for await payload in group {
                if Task.isCancelled { break }
                if let payload {
                    group.cancelAll()
                    return payload
                }
            }
            return nil
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
        // ProviderSDK has up to 8 candidates to give the unified ranker more signal.
        let sectionLimit = service == .providerSDK ? 8 : 5

        switch result {
        case let .success(items):
            federatedSections[index].items = Array(items.prefix(sectionLimit))
            federatedSections[index].state = .success
        case let .failure(error):
            federatedSections[index].items = []
            federatedSections[index].state = .error(error.localizedDescription)
        }
    }

    private func setSectionState(_ state: FederatedSectionState, for service: FederatedService) {
        guard let index = federatedSections.firstIndex(where: { $0.service == service }) else { return }
        federatedSections[index].state = state
        federatedSections[index].items = []
    }

    public func firstSectionErrorMessage() -> String? {
        for service in UnifiedTopResultsPolicy.services {
            guard let section = federatedSections.first(where: { $0.service == service }) else {
                continue
            }

            if case let .error(message) = section.state {
                return message
            }
        }
        return nil
    }

    private struct UnifiedRankingContext {
        let normalizedQuery: String
        let youtubeArtistSignals: [String: Double]
        let dominantArtist: String?
        let queryHasArtistHint: Bool
    }

    private nonisolated func buildUnifiedTopResults(for query: String, in sections: [FederatedSearchSection]) -> [FederatedSearchItem] {
        let candidates = UnifiedTopResultsPolicy.services.flatMap { service in
            sections.first(where: { $0.service == service })?.items ?? []
        }
        guard !candidates.isEmpty else { return [] }

        let context = makeUnifiedRankingContext(for: query, candidates: candidates)
        var groupedCandidates: [String: [(item: FederatedSearchItem, score: Double)]] = [:]

        for item in candidates {
            let key = unifiedResultDedupKey(for: item)
            let score = unifiedResultScore(for: item, context: context)
            PerfLog.info("SearchRanking: [\(item.service.rawValue)] '\(item.title) - \(primaryArtistName(from: item.subtitle))' -> Total Score: \(String(format: "%.3f", score))")
            groupedCandidates[key, default: []].append((item: item, score: score))
        }

        let rankedGroups: [(item: FederatedSearchItem, score: Double)] = groupedCandidates.values.compactMap { group in
            guard let representative = group.max(by: { $0.score < $1.score }) else {
                return nil
            }

            let distinctServiceCount = Set(group.map(\.item.service)).count
            let consensusBoost = consensusConfidenceBoost(forDistinctServiceCount: distinctServiceCount)
            return (item: representative.item, score: representative.score + consensusBoost)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return providerPriority(for: lhs.item.service) < providerPriority(for: rhs.item.service)
            }
            return lhs.score > rhs.score
        }

        let finalResults = enforceServiceDiversity(
            on: rankedGroups.map(\.item),
            limit: UnifiedTopResultsPolicy.limit,
            queryHasArtistHint: context.queryHasArtistHint
        )

        PerfLog.info("SearchViewModel: Unified ranking order for '\(query)':")
        for (index, item) in finalResults.enumerated() {
            PerfLog.info("  [\(index)] \(item.title) - \(item.subtitle) (Source: \(item.service))")
        }

        return finalResults
    }

    private nonisolated func buildYouMightLikeResults(
        for query: String,
        in sections: [FederatedSearchSection],
        anchorResults: [FederatedSearchItem],
        excludingIDs: Set<String>
    ) -> [FederatedSearchItem] {
        let candidates = YouMightLikePolicy.services
            .flatMap { service in
                sections.first(where: { $0.service == service })?.items ?? []
            }
            .filter { !excludingIDs.contains($0.id) }
        guard !candidates.isEmpty else { return [] }

        let normalizedQuery = normalizedRankingText(query)
        let anchorTitle = normalizedRankingText(anchorResults.first?.title ?? "")
        let anchorArtist = normalizedRankingText(primaryArtistName(from: anchorResults.first?.subtitle ?? ""))

        let ranked = candidates.enumerated().map { index, item in
            let itemTitle = normalizedRankingText(item.title)
            let itemArtist = normalizedRankingText(primaryArtistName(from: item.subtitle))

            let querySimilarity = tokenOverlapScore(itemTitle, normalizedQuery)
            let anchorSimilarity = max(
                tokenOverlapScore(itemTitle, anchorTitle),
                tokenOverlapScore(itemArtist, anchorArtist)
            )
            let serviceBoost = item.service == .youtube ? 0.08 : 0.05
            let positionBoost = max(0.0, 0.12 - (Double(index) * 0.02))
            let score = (0.58 * querySimilarity) + (0.30 * anchorSimilarity) + serviceBoost + positionBoost

            return (item: item, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return providerPriority(for: lhs.item.service) < providerPriority(for: rhs.item.service)
            }
            return lhs.score > rhs.score
        }
        .map(\.item)

        let deduplicated = dedupeByMetadataPreservingOrder(ranked)
        return Array(deduplicated.prefix(YouMightLikePolicy.limit))
    }

    private nonisolated func dedupeByMetadataPreservingOrder(_ items: [FederatedSearchItem]) -> [FederatedSearchItem] {
        var seen = Set<String>()
        var deduped: [FederatedSearchItem] = []

        for item in items {
            let key = unifiedResultDedupKey(for: item)
            if seen.insert(key).inserted {
                deduped.append(item)
            }
        }

        return deduped
    }

    private nonisolated func makeUnifiedRankingContext(for query: String, candidates: [FederatedSearchItem]) -> UnifiedRankingContext {
        let normalizedQuery = normalizedRankingText(query)
        let youtubeArtistSignals = buildYouTubeArtistSignals(from: candidates)
        let dominantArtist = youtubeArtistSignals
            .max(by: { lhs, rhs in lhs.value < rhs.value })?
            .key
        let queryHasArtistHint = queryContainsArtistHint(
            normalizedQuery,
            candidateArtists: Array(youtubeArtistSignals.keys)
        )

        return UnifiedRankingContext(
            normalizedQuery: normalizedQuery,
            youtubeArtistSignals: youtubeArtistSignals,
            dominantArtist: dominantArtist,
            queryHasArtistHint: queryHasArtistHint
        )
    }

    private nonisolated func buildYouTubeArtistSignals(from candidates: [FederatedSearchItem]) -> [String: Double] {
        var signals: [String: Double] = [:]

        let youtubeItems = candidates.filter { $0.service == .youtube }
        for (index, item) in youtubeItems.enumerated() {
            guard case let .youtubeVideo(video) = item.payload else { continue }

            let artist = normalizedRankingText(normalizedMusicDisplayArtist(video.author, title: video.title))
            guard !artist.isEmpty else { continue }

            let viewCount = parseYouTubeViewCount(video.viewCount)
            let positionWeight = max(0.30, 1.0 - (Double(index) * 0.16))
            let viewWeight = log10(max(10.0, viewCount + 10.0))
            let totalWeight = positionWeight + (viewWeight * 0.22)

            signals[artist, default: 0] += totalWeight
        }

        let youtubeMusicItems = candidates.filter { $0.service == .youtubeMusic }
        for (index, item) in youtubeMusicItems.enumerated() {
            let artist = normalizedRankingText(primaryArtistName(from: item.subtitle))
            guard !artist.isEmpty else { continue }
            let weight = max(0.20, 0.55 - (Double(index) * 0.10))
            signals[artist, default: 0] += weight
        }

        return signals
    }

    private nonisolated func queryContainsArtistHint(_ normalizedQuery: String, candidateArtists: [String]) -> Bool {
        if normalizedQuery.contains(" by ") {
            return true
        }

        let queryTokens = tokenSet(from: normalizedQuery)
        guard queryTokens.count >= 3 else { return false }

        for artist in candidateArtists {
            let artistTokenSet = Set(tokenSet(from: artist).filter { $0.count > 2 })
            guard !artistTokenSet.isEmpty else { continue }

            let overlap = Double(queryTokens.intersection(artistTokenSet).count) / Double(artistTokenSet.count)
            if overlap >= 0.67 {
                return true
            }
        }

        return false
    }

    private nonisolated func unifiedResultScore(for item: FederatedSearchItem, context: UnifiedRankingContext) -> Double {
        let searchableText = normalizedRankingText("\(item.title) \(primaryArtistName(from: item.subtitle))")
        let queryTokens = tokenSet(from: context.normalizedQuery)
        let itemTokens = tokenSet(from: searchableText)

        let overlap: Double = if queryTokens.isEmpty {
            0
        } else {
            Double(queryTokens.intersection(itemTokens).count) / Double(queryTokens.count)
        }

        let containsBoost = (!context.normalizedQuery.isEmpty && searchableText.contains(context.normalizedQuery)) ? 0.16 : 0
        let prefixBoost = (!context.normalizedQuery.isEmpty && searchableText.hasPrefix(context.normalizedQuery)) ? 0.06 : 0
        let providerBoost = providerConfidenceBoost(for: item.service, queryHasArtistHint: context.queryHasArtistHint)
        let qualityBoost = qualityConfidenceBoost(for: item)
        let playabilityBoost = item.isPlayable ? 0.03 : -0.12

        let artistAlignment = itemArtistAlignmentScore(for: item, dominantArtist: context.dominantArtist)
        let artistBoost = inferredArtistBoost(
            for: item.service,
            alignment: artistAlignment,
            hasDominantArtist: context.dominantArtist != nil,
            queryHasArtistHint: context.queryHasArtistHint
        )

        let totalScore = (0.68 * overlap)
            + containsBoost
            + prefixBoost
            + providerBoost
            + qualityBoost
            + playabilityBoost
            + artistBoost

        PerfLog.info("SearchRankingBreakdown: '\(item.title)' -> overlap:\(String(format: "%.2f", 0.68 * overlap)) contains:\(containsBoost) prefix:\(prefixBoost) provider:\(providerBoost) quality:\(qualityBoost) playability:\(playabilityBoost) artist:\(String(format: "%.2f", artistBoost))")

        return totalScore
    }

    private nonisolated func itemArtistAlignmentScore(for item: FederatedSearchItem, dominantArtist: String?) -> Double {
        guard let dominantArtist, !dominantArtist.isEmpty else { return 0 }
        let itemArtist = normalizedRankingText(primaryArtistName(from: item.subtitle))
        guard !itemArtist.isEmpty else { return 0 }
        return tokenOverlapScore(itemArtist, dominantArtist)
    }

    private nonisolated func inferredArtistBoost(
        for service: FederatedService,
        alignment: Double,
        hasDominantArtist: Bool,
        queryHasArtistHint _: Bool
    ) -> Double {
        guard hasDominantArtist else { return 0 }

        switch service {
        case .youtubeMusic:
            if alignment >= 0.75 { return 0.08 }
            if alignment >= 0.45 { return 0.04 }
            return 0
        case .youtube:
            if alignment >= 0.75 { return 0.06 }
            if alignment >= 0.45 { return 0.03 }
            return 0
        case .spotify:
            return 0
        case .providerSDK:
            // ProviderSDK has exact metadata from the native provider; trust it highly.
            if alignment >= 0.75 { return 0.09 }
            if alignment >= 0.45 { return 0.05 }
            return 0
        }
    }

    private nonisolated func consensusConfidenceBoost(forDistinctServiceCount count: Int) -> Double {
        switch count {
        case 3...:
            0.10
        case 2:
            0.06
        default:
            0
        }
    }

    private nonisolated func enforceServiceDiversity(
        on rankedItems: [FederatedSearchItem],
        limit: Int,
        queryHasArtistHint _: Bool
    ) -> [FederatedSearchItem] {
        guard limit > 0 else { return [] }

        var selected: [FederatedSearchItem] = []
        var selectedIDs = Set<String>()
        var serviceCounts: [FederatedService: Int] = [:]

        for item in rankedItems {
            let cap = UnifiedTopResultsPolicy.maxPerService[item.service] ?? limit

            if serviceCounts[item.service, default: 0] >= cap {
                continue
            }

            if selectedIDs.insert(item.id).inserted {
                selected.append(item)
                serviceCounts[item.service, default: 0] += 1
            }

            if selected.count == limit {
                return selected
            }
        }

        if selected.count < limit {
            for item in rankedItems {
                guard selectedIDs.insert(item.id).inserted else { continue }
                selected.append(item)
                if selected.count == limit {
                    break
                }
            }
        }

        // Log the final selected group for debugging
        PerfLog.info("SearchRanking: --- Final Top Results ---")
        for (i, finalItem) in selected.enumerated() {
            PerfLog.info("SearchRanking: #\(i + 1) [\(finalItem.service.rawValue)] '\(finalItem.title)'")
        }

        return selected
    }

    private nonisolated func unifiedResultDedupKey(for item: FederatedSearchItem) -> String {
        let title = normalizedRankingText(item.title)
        let artist = normalizedRankingText(primaryArtistName(from: item.subtitle))
        return "\(title)|\(artist)"
    }

    nonisolated func primaryArtistName(from subtitle: String) -> String {
        if let first = subtitle.split(separator: "•").first {
            let artist = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty {
                return artist
            }
        }

        return subtitle
    }

    private nonisolated func parseYouTubeViewCount(_ value: String) -> Double {
        let lowercased = value
            .lowercased()
            .replacingOccurrences(of: ",", with: "")

        if let compactRange = lowercased.range(of: "([0-9]+(?:\\.[0-9]+)?)\\s*([kmb])", options: .regularExpression) {
            let compact = String(lowercased[compactRange])
            let numericPart = compact.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            guard let number = Double(numericPart) else { return 0 }

            if compact.contains("b") { return number * 1_000_000_000 }
            if compact.contains("m") { return number * 1_000_000 }
            if compact.contains("k") { return number * 1000 }
            return number
        }

        if let numberRange = lowercased.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression),
           let number = Double(lowercased[numberRange])
        {
            if lowercased.contains("billion") { return number * 1_000_000_000 }
            if lowercased.contains("million") { return number * 1_000_000 }
            if lowercased.contains("thousand") { return number * 1000 }
            return number
        }

        return 0
    }

    nonisolated func providerPriority(for service: FederatedService) -> Int {
        switch service {
        case .youtubeMusic:
            1
        case .youtube:
            2
        case .spotify:
            3
        case .providerSDK:
            4
        }
    }

    private nonisolated func providerConfidenceBoost(for service: FederatedService, queryHasArtistHint: Bool) -> Double {
        switch service {
        case .youtube:
            queryHasArtistHint ? 0.03 : 0.04
        case .youtubeMusic:
            queryHasArtistHint ? 0.02 : 0.03
        case .spotify:
            0
        case .providerSDK:
            // ProviderSDK tracks already carry quality metadata — the quality boost
            // handles the ranking lift; provider boost stays neutral here.
            0.01
        }
    }

    private func upsertCanonicalYouTubeMusicSongs(_ songs: [YouTubeMusicSong]) {
        guard let centralMediaStore else { return }

        Task {
            for song in songs {
                let artistName = primaryArtistName(from: song.artistsDisplay)
                _ = await centralMediaStore.upsertSong(
                    .init(
                        title: song.title,
                        normalizedTitle: normalizedRankingText(song.title),
                        primaryArtistName: artistName.isEmpty ? nil : artistName,
                        primaryArtistID: nil,
                        albumTitle: song.album,
                        albumID: nil,
                        durationSeconds: song.duration,
                        artworkURLString: song.thumbnailURL?.absoluteString,
                        isExplicit: song.isExplicit,
                        providerFingerprint: songFingerprint(title: song.title, artist: artistName),
                        spotifyTrackID: nil,
                        spotifyTrackURI: nil,
                        spotifyPreviewURLString: nil,
                        youtubeVideoID: nil,
                        youtubeMusicVideoID: song.videoId,
                        appleMusicSongID: nil
                    )
                )
            }
        }
    }

    private func upsertCanonicalYouTubeVideos(_ videos: [YouTubeVideo]) {
        guard let centralMediaStore else { return }

        Task {
            for video in videos {
                let artistName = video.author
                _ = await centralMediaStore.upsertSong(
                    .init(
                        title: video.title,
                        normalizedTitle: normalizedRankingText(video.title),
                        primaryArtistName: artistName.isEmpty ? nil : artistName,
                        primaryArtistID: nil,
                        albumTitle: nil,
                        albumID: nil,
                        durationSeconds: parseVideoDurationSeconds(video.lengthInSeconds),
                        artworkURLString: video.thumbnailURL,
                        isExplicit: false,
                        providerFingerprint: songFingerprint(title: video.title, artist: artistName),
                        spotifyTrackID: nil,
                        spotifyTrackURI: nil,
                        spotifyPreviewURLString: nil,
                        youtubeVideoID: video.id,
                        youtubeMusicVideoID: nil,
                        appleMusicSongID: nil
                    )
                )
            }
        }
    }

    private func songFingerprint(title: String, artist: String) -> String {
        let normalizedTitle = normalizedRankingText(title)
        let normalizedArtist = normalizedRankingText(artist)
        return normalizedArtist.isEmpty ? normalizedTitle : "\(normalizedTitle)|\(normalizedArtist)"
    }

    private nonisolated func qualityConfidenceBoost(for item: FederatedSearchItem) -> Double {
        let quality = normalizedRankingText(item.audioQualityLabel ?? "")
        let codec = normalizedRankingText(item.audioCodecLabel ?? "")

        var boost: Double = 0

        if quality.contains("hi res") || quality.contains("hi-res") {
            boost += 0.15
        } else if quality.contains("lossless") || quality == "cd" {
            boost += 0.10
        } else if quality.contains("high") {
            boost += 0.05
        }

        if codec == "flac" {
            boost += 0.02
        } else if codec == "aac" {
            boost += 0.005
        }

        return boost
    }

    private nonisolated func fetchYouTubeMusicSectionItems(query: String, updateUI: Bool) async -> Result<[FederatedSearchItem], Error> {
        do {
            let results = try await youtube.music.search(query)
            if updateUI {
                await MainActor.run {
                    self.musicResults = results
                    self.searchCache.setMusicResults(results, for: query)
                }
                await searchCacheHintStore.recordMusicResults(query: query, results: results)

                let topResultsForPrefetch = Array(results.prefix(2))
                let prefetchIDs = topResultsForPrefetch.map(\.videoId)
                await MainActor.run {
                    self.prefetchTopResultIDs(prefetchIDs)
                }

                let topResultsForUI = Array(results.prefix(5))
                await MainActor.run {
                    self.upsertCanonicalYouTubeMusicSongs(topResultsForUI)
                }
            }

            let items = results.prefix(5).map { song in
                FederatedSearchItem(
                    id: "ytm-\(song.videoId)",
                    title: normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay),
                    subtitle: "\(normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title)) • \(song.album ?? "Single")",
                    artworkURL: song.thumbnailURL,
                    durationSeconds: song.duration,
                    isPlayable: true,
                    isExplicit: song.isExplicit,
                    audioQualityLabel: nil,
                    audioCodecLabel: nil,
                    payload: .youtubeMusic(song)
                )
            }

            return .success(items)
        } catch {
            return .failure(error)
        }
    }

    private nonisolated func fetchYouTubeSectionItems(query: String, updateUI: Bool) async -> Result<[FederatedSearchItem], Error> {
        do {
            let continuation = try await youtube.main.search(query)

            let topVideos: [YouTubeVideo]
            if updateUI {
                let videoResults = await MainActor.run {
                    self.resetVideoPagination()
                    self.updateVideoResults(with: continuation, appending: false)
                    let results = self.videoResults
                    self.searchCache.setVideoResults(results, for: query)
                    return results
                }
                await searchCacheHintStore.recordVideoResults(query: query, results: videoResults)

                topVideos = Array(videoResults.compactMap { item -> YouTubeVideo? in
                    if case let .video(video) = item { return video }
                    return nil
                }.prefix(5))
            } else {
                topVideos = Array(continuation.items.compactMap { item -> YouTubeVideo? in
                    if case let .video(video) = item { return video }
                    return nil
                }.prefix(5))
            }

            let items = topVideos.map { video in
                FederatedSearchItem(
                    id: "yt-\(video.id)",
                    title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                    subtitle: normalizedMusicDisplayArtist(video.author, title: video.title),
                    artworkURL: normalizedArtworkURL(from: video.thumbnailURL),
                    durationSeconds: self.parseVideoDurationSeconds(video.lengthInSeconds),
                    isPlayable: true,
                    isExplicit: false,
                    audioQualityLabel: nil,
                    audioCodecLabel: nil,
                    payload: .youtubeVideo(video)
                )
            }

            return .success(Array(items))
        } catch {
            let fallbackQuery = rawVideoSearchQuery(from: query)
            guard fallbackQuery != query else {
                return .failure(error)
            }

            PerfLog.info("SearchViewModel: video search retrying with raw query '\(fallbackQuery)' after rewritten query '\(query)' failed")

            do {
                let continuation = try await youtube.main.search(fallbackQuery)

                let topVideos: [YouTubeVideo]
                if updateUI {
                    let videoResults = await MainActor.run {
                        self.resetVideoPagination()
                        self.updateVideoResults(with: continuation, appending: false)
                        let results = self.videoResults
                        self.searchCache.setVideoResults(results, for: fallbackQuery)
                        Task {
                            await self.searchCacheHintStore.recordVideoResults(query: fallbackQuery, results: results)
                        }
                        return results
                    }

                    topVideos = Array(videoResults.compactMap { item -> YouTubeVideo? in
                        if case let .video(video) = item { return video }
                        return nil
                    }.prefix(5))
                } else {
                    topVideos = Array(continuation.items.compactMap { item -> YouTubeVideo? in
                        if case let .video(video) = item { return video }
                        return nil
                    }.prefix(5))
                }

                let items = topVideos.map { video in
                    FederatedSearchItem(
                        id: "yt-\(video.id)",
                        title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                        subtitle: normalizedMusicDisplayArtist(video.author, title: video.title),
                        artworkURL: normalizedArtworkURL(from: video.thumbnailURL),
                        durationSeconds: self.parseVideoDurationSeconds(video.lengthInSeconds),
                        isPlayable: true,
                        isExplicit: false,
                        audioQualityLabel: nil,
                        audioCodecLabel: nil,
                        payload: .youtubeVideo(video)
                    )
                }

                return .success(Array(items))
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - ProviderSDK Search & Resolution

    /// Fetches and maps search results from all registered ProviderSDK providers (SoundCloud,
    /// Tidal, Qobuz, Deezer, etc.) into `FederatedSearchItem` objects with quality badges.
    ///
    /// The ProviderSDK's `SearchFederation` runs each registered provider in parallel and
    /// yields deduplicated batches via an `AsyncThrowingStream`. We collect all batches,
    /// using the C-3 fix (append not overwrite) so partial results are preserved on error.
    private nonisolated func fetchProviderSDKSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
        guard let sdk = await MainActor.run(resultType: ProviderSDK?.self, body: { self.providerSDK }) else {
            return .success([]) // No SDK injected — silently skip (backward-compat)
        }

        let stream = await sdk.searchTracks(query: query, limit: 10)
        var allTracks: [Track] = []

        do {
            for try await batch in stream {
                PerfLog.info("SearchViewModel: ProviderSDK received batch of \(batch.count) tracks")
                allTracks.append(contentsOf: batch)
            }
        } catch {
            // Non-fatal — use whatever was accumulated before the stream error.
            PerfLog.info("SearchViewModel: ProviderSDK search stream error (partial results kept): \(error.localizedDescription)")
        }

        PerfLog.info("SearchViewModel: ProviderSDK search completed with \(allTracks.count) tracks")

        guard !allTracks.isEmpty else { return .success([]) }

        let items = allTracks.prefix(10).map { track -> FederatedSearchItem in
            let artistName = track.artists.first?.name ?? ""
            let albumTitle = track.album.title
            let subtitle = artistName.isEmpty
                ? albumTitle
                : "\(artistName) • \(albumTitle)"

            // Prefer album cover art; fall back to the first representation that has artwork.
            let artworkURL = track.album.coverArtURL
                ?? track.representations.compactMap(\.artworkURL).first

            let (qualityLabel, codecLabel) = providerSDKQualityBadge(for: track)

            return FederatedSearchItem(
                id: "pdk-\(track.id.value)",
                title: track.title,
                subtitle: subtitle,
                artworkURL: artworkURL,
                durationSeconds: track.duration,
                isPlayable: true,
                isExplicit: track.isExplicit,
                audioQualityLabel: qualityLabel,
                audioCodecLabel: codecLabel,
                payload: .providerSDKTrack(track)
            )
        }

        return .success(Array(items))
    }

    /// Derives a quality badge for a ProviderSDK `Track` based on the representations
    /// it carries from its source provider.
    ///
    /// Returns `(qualityLabel, codecLabel)` — e.g. `("Hi-Res", "FLAC")`.
    private nonisolated func providerSDKQualityBadge(for track: Track) -> (String, String) {
        // Prefer the representation with the highest-known audioQuality value.
        let bestQuality = track.representations
            .compactMap(\.audioQuality)
            .max(by: { $0.priority < $1.priority })

        switch bestQuality {
        case .hiResLossless:
            return ("Hi-Res", "FLAC")
        case .lossless:
            // Distinguish CD-quality (44.1 kHz) from general lossless
            let isCDQuality = track.representations.contains { rep in
                rep.providerID == "tidal" || rep.providerID == "qobuz" || rep.providerID == "deezer"
            }
            return isCDQuality ? ("CD", "FLAC") : ("Lossless", "FLAC")
        case .high:
            return ("High", "AAC")
        case .standard:
            return ("Standard", "MP3")
        case .low:
            return ("Standard", "MP3")
        case nil:
            // SoundCloud and unknown providers default to standard quality
            return ("Standard", "MP3")
        }
    }

    /// Resolves a ProviderSDK `Track` directly to a playable `ExternalStreamPayload`
    /// without going through the YouTube fallback chain.
    private func resolveProviderSDKExternalStream(
        for track: Track,
        fallbackSpotifyItem _: FederatedSearchItem?
    ) async throws -> ExternalStreamPayload? {
        let title = track.title
        let artist = track.artists.first?.name ?? "Unknown"
        // Prefer album cover art; fall back to the first representation that has artwork.
        let artworkURL = track.album.coverArtURL
            ?? track.representations.compactMap(\.artworkURL).first

        // Use ProviderSDKStreamResolver directly — it handles ISRC-first lookup,
        // federated search fallback, and AudioStream → PlaybackCandidate mapping.
        let resolver = await PlaybackURLResolver.sharedInstance()
        let representations = track.representations.map { rep in
            TrackRepresentation(
                providerID: rep.providerID,
                providerTrackID: rep.providerTrackID,
                title: rep.title,
                artist: rep.artist,
                duration: rep.duration,
                isrc: rep.isrc,
                artworkURL: rep.artworkURL,
                audioQuality: rep.audioQuality
            )
        }

        let candidates = try await resolver.resolve(
            mediaID: track.id.value,
            title: title,
            artist: artist,
            representations: representations,
            forceDecipher: false,
            duration: track.duration
        )

        guard let best = candidates.first, let url = Optional(best.url) else {
            throw FederatedSearchError.noPlayableStream("No stream found for \"\(title)\" via ProviderSDK.")
        }

        // Derive quality label from the resolved candidate's MIME type.
        let mime = best.mimeType?.lowercased() ?? ""
        let qualityLabel: String
        let codecLabel: String
        if mime.contains("flac") || mime.contains("alac") {
            qualityLabel = "Lossless"; codecLabel = "FLAC"
        } else if mime.contains("aac") {
            qualityLabel = "High"; codecLabel = "AAC"
        } else {
            qualityLabel = "Standard"; codecLabel = "MP3"
        }

        return ExternalStreamPayload(
            mediaID: track.id.value,
            streamURL: url,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            service: .providerSDK,
            qualityLabel: qualityLabel,
            codecLabel: codecLabel
        )
    }

    /// Result type carrying all three Spotify visible sections
    public struct SpotifySearchItems {
        let tracks: [FederatedSearchItem]
        let artists: [FederatedSearchItem]
        let playlists: [FederatedSearchItem]
    }

    private nonisolated func fetchSpotifySectionItems(query: String) async -> Result<SpotifySearchItems, Error> {
        #if canImport(SpotifySDK)
        do {
            let spotify = try await makeSpotifyClient()
            let results = try await spotify.search.search(
                query,
                limit: 8,
                numberOfTopResults: 5,
                includeAudiobooks: false
            )

            let sourceTracks = Array((results.tracks?.items ?? []).prefix(8))
            let sourceArtists = Array((results.artists?.items ?? []).prefix(4))
            let sourcePlaylists = Array((results.playlists?.items ?? []).prefix(4))

            if let centralMediaStore {
                _ = await centralMediaStore.upsertSpotifyTracks(sourceTracks)
                _ = await centralMediaStore.upsertSpotifyArtists(sourceArtists)
                _ = await centralMediaStore.upsertSpotifyPlaylists(sourcePlaylists)
            }

            // Tracks
            let trackItems: [FederatedSearchItem] = sourceTracks.map { track in
                let spotifyTrack = SpotifySearchTrack(
                    id: track.id,
                    title: track.name,
                    artistName: track.artists.first?.name ?? "Unknown Artist",
                    albumName: track.album?.name,
                    artworkURL: track.album?.images.first?.url,
                    durationSeconds: TimeInterval(track.durationMS) / 1000,
                    previewURL: track.previewURL,
                    isrc: track.isrc
                )
                return FederatedSearchItem(
                    id: "spotify-\(track.id)",
                    title: spotifyTrack.title,
                    subtitle: "\(spotifyTrack.artistName) • \(spotifyTrack.albumName ?? "Spotify")",
                    artworkURL: spotifyTrack.artworkURL,
                    durationSeconds: spotifyTrack.durationSeconds,
                    isPlayable: true, // resolved via hidden providers
                    isExplicit: track.isExplicit ?? false,
                    audioQualityLabel: nil,
                    audioCodecLabel: nil,
                    payload: .spotify(spotifyTrack)
                )
            }

            // Artists
            let artistItems: [FederatedSearchItem] = sourceArtists.map { artist in
                let artworkURL = artist.images.first?.url
                return FederatedSearchItem(
                    id: "spotify-artist-\(artist.id)",
                    title: artist.name,
                    subtitle: "Artist",
                    artworkURL: artworkURL,
                    durationSeconds: nil,
                    isPlayable: false,
                    isExplicit: false,
                    audioQualityLabel: nil,
                    audioCodecLabel: nil,
                    payload: .spotifyArtist(SpotifySearchArtist(
                        id: artist.id,
                        name: artist.name,
                        artworkURL: artworkURL,
                        genres: artist.genres
                    ))
                )
            }

            // Playlists
            let playlistItems: [FederatedSearchItem] = sourcePlaylists.map { playlist in
                let artworkURL = playlist.images.first?.url
                let ownerName = playlist.owner?.displayName ?? "Spotify"
                return FederatedSearchItem(
                    id: "spotify-playlist-\(playlist.id)",
                    title: playlist.name,
                    subtitle: "Playlist • \(ownerName)",
                    artworkURL: artworkURL,
                    durationSeconds: nil,
                    isPlayable: false,
                    isExplicit: false,
                    audioQualityLabel: nil,
                    audioCodecLabel: nil,
                    payload: .spotifyPlaylist(SpotifySearchPlaylist(
                        id: playlist.id,
                        uri: playlist.uri,
                        name: playlist.name,
                        ownerName: ownerName,
                        artworkURL: artworkURL,
                        totalTracks: playlist.totalTracks
                    ))
                )
            }

            return .success(SpotifySearchItems(
                tracks: trackItems,
                artists: artistItems,
                playlists: playlistItems
            ))
        } catch {
            return .failure(error)
        }
        #else
        return .failure(FederatedSearchError.providerUnavailable("SpotifySDK is not linked to this target."))
        #endif
    }

    private nonisolated func parseVideoDurationSeconds(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        return Double(value)
    }

    private func inferCodecLabel(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "flac" { return "FLAC" }
        if ext == "m3u8" { return "HLS" }
        if ext == "aac" || ext == "m4a" || ext == "mp4" { return "AAC" }
        if ext == "mp3" { return "MP3" }
        return "Unknown"
    }

    private func inferCodecLabelIfKnown(from url: URL?) -> String? {
        guard let url else { return nil }
        let label = inferCodecLabel(from: url)
        return label == "Unknown" ? nil : label
    }

    #if canImport(SpotifySDK)
    private func makeSpotifyClient() async throws -> SpotifySDK {
        let coordinator = SpotifySessionCoordinator.shared
        if !coordinator.didAttemptRestore {
            await coordinator.restoreSessionIfNeeded()
        }

        if streamingProviderSettings.spotifyPreferAnonymousFallback {
            if let fallbackSdk = coordinator.anonymousFallbackSdk {
                return fallbackSdk
            }
            // This is a stateless fallback client for public search if the coordinator doesn't have one ready
            return SpotifySDK(mode: .anonymous)
        }

        if let sdk = coordinator.sdk {
            return sdk
        }

        throw FederatedSearchError.spotifyCredentialsMissing
    }

    /// Fetches Spotify search suggestions; returns [] silently on any failure.
    private func fetchSpotifySuggestions(query: String) async -> [String] {
        guard let spotify = try? await makeSpotifyClient() else { return [] }
        let suggestions = try? await spotify.search.searchSuggestions(query, limit: 10, numberOfTopResults: 10)
        return suggestions?.map(\.title) ?? []
    }
    #endif

    public func applySuggestion(_ suggestion: String) {
        let cleaned = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        searchTask?.cancel()
        searchText = cleaned
        Task {
            await historyStore.recordSearch(query: cleaned)
            await executeSearch()
        }
    }

    /// Prefetch metadata and resolved stream urls for top items.
    private func prefetchTopResultIDs(_ ids: [String]) {
        prefetchTask?.cancel()
        guard !ids.isEmpty else { return }
        let youtube = youtube
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
            // Also prewarm quick-playback URLs (HLS preferred) so the player can start immediately.
            let resolver = await PlaybackURLResolver.sharedInstance()
            await resolver.prewarm(ids)
        }
    }

    /// Public helper to prefetch a single id (used by row onAppear)
    public func prefetchIfNeeded(id _: String) {}

    private func scheduleInlinePrefetchDrainIfNeeded() {
        guard inlinePrefetchDrainTask == nil else { return }

        let youtube = youtube
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

            // Warm quick-playback URLs for these inline-prefetch IDs as well.
            let resolver = await PlaybackURLResolver.sharedInstance()
            await resolver.prewarm(ids)

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
            // Fetch from Spotify, YouTube, and YouTube Music in parallel
            #if canImport(SpotifySDK)
            async let spotifySuggestionsTask: [String] = fetchSpotifySuggestions(query: query)
            #else
            async let spotifySuggestionsTask: [String] = []
            #endif
            let mainClient = youtube.main
            let musicClient = youtube.music
            async let youtubeSuggestionsTask = mainClient.getSearchSuggestions(query: query)
            async let musicSuggestionsTask = musicClient.getSearchSuggestions(query: query)

            let spotifySuggestions = await spotifySuggestionsTask
            let youtubeSuggestions = await (try? youtubeSuggestionsTask) ?? []
            let musicSuggestions = await (try? musicSuggestionsTask) ?? []

            // Merge: Spotify first (richest), then YouTube deduped
            var seenSuggestionKeys = Set<String>()
            let merged = (spotifySuggestions + youtubeSuggestions + musicSuggestions).filter { suggestion in
                let key = suggestion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { return false }
                return seenSuggestionKeys.insert(key).inserted
            }
            let remote = merged

            let local = await historyStore.topCandidates(prefix: query, limit: 20)
            var candidates: [SuggestionCandidate] = []

            candidates.append(contentsOf: remote.map {
                SuggestionCandidate(
                    text: $0,
                    frequency: 0,
                    successfulPlays: 0,
                    recency: Date.distantPast,
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
            let top = await historyStore.topCandidates(prefix: query, limit: 8).map(\.query)
            await MainActor.run {
                self.suggestions = top
            }
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
        let youtube = youtube

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
                    await searchCacheHintStore.recordMusicResults(query: normalizedTop, results: results)
                }
                ids = Array(results.prefix(3).map(\.videoId))

            case .video:
                let results: [YouTubeSearchResult]
                if let cached = searchCache.getVideoResults(for: normalizedTop), !cached.isStale {
                    results = cached.results
                } else {
                    let continuation = try await youtube.main.search(effectiveSearchQuery(for: normalizedTop, scope: scope))
                    let mapped = mapSearchResults(from: continuation.items)
                    searchCache.setVideoResults(mapped, for: normalizedTop)
                    await searchCacheHintStore.recordVideoResults(query: normalizedTop, results: mapped)
                    results = mapped
                }
                ids = Array(results.compactMap { item -> String? in
                    if case let .video(v) = item { return v.id }
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

    public func loadMoreVideosIfNeeded(for item: YouTubeSearchResult) {
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
           Date().timeIntervalSince(lastTime) < paginationTriggerCooldown
        {
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
            videoResults.append(contentsOf: mapped)
        } else {
            // Initial load replace without animation to avoid strange layout jumps.
            videoResults = mapped
        }

        videoContinuationToken = continuation.continuationToken
        // Re-arm trigger protection for the next token progression.
        lastPaginationTriggerToken = continuation.continuationToken
        // Successful parse/append — reset any bad-response tracking
        videoContinuationBadResponseCount = 0
    }

    private func mapSearchResults(from items: [YouTubeItem]) -> [YouTubeSearchResult] {
        items.compactMap { item in
            switch item {
            case let .video(v):
                guard shouldKeepVideoResult(v) else { return nil }
                return .video(v)
            case let .channel(c):
                guard shouldKeepMusicChannel(c) else { return nil }
                return .channel(c)
            case let .playlist(p):
                guard shouldKeepMusicPlaylist(p) else { return nil }
                return .playlist(p)
            default: return nil
            }
        }
    }

    private nonisolated func effectiveSearchQuery(for query: String, scope: Models.SearchScope) -> String {
        switch scope {
        case .music:
            query
        case .video:
            musicVideoSearchQuery(query)
        }
    }

    private nonisolated func rawVideoSearchQuery(from query: String) -> String {
        query.replacingOccurrences(of: " (Official Music Video)", with: "")
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

    public func recordSuccessfulPlayFromCurrentQuery() {
        // Track successful play to improve future search rankings
    }
}
