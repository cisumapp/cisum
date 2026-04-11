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

    private enum UnifiedTopResultsPolicy {
        static let limit: Int = 5
        static let services: [FederatedService] = [.tidal, .youtubeMusic, .youtube]
        static let maxPerService: [FederatedService: Int] = [
            .tidal: 2,
            .youtubeMusic: 3,
            .youtube: 3
        ]
    }

    private enum YouMightLikePolicy {
        static let limit: Int = 8
        static let services: [FederatedService] = [.youtubeMusic, .youtube]
    }

    private let youtube: YouTube
    private let settings: PrefetchSettings
    private let networkMonitor: NetworkPathMonitor
    private let historyStore: SearchHistoryStore
    private let searchCacheHintStore: SearchCacheHintStore
    private let streamingProviderSettings: StreamingProviderSettings
    private let metadataCache: any VideoMetadataCaching
    private let searchCache: any SearchResultsCaching

    init(
        youtube: YouTube,
        settings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor,
        historyStore: SearchHistoryStore,
        searchCacheHintStore: SearchCacheHintStore,
        streamingProviderSettings: StreamingProviderSettings,
        metadataCache: any VideoMetadataCaching,
        searchCache: any SearchResultsCaching
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
    var unifiedTopResults: [FederatedSearchItem] = []
    var youMightLikeResults: [FederatedSearchItem] = []
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
            self.unifiedTopResults = []
            self.youMightLikeResults = []
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
            self.unifiedTopResults = []
            self.youMightLikeResults = []
            self.state = .idle
            return
        }

        if case .success = state,
           lastCompletedQuery == query {
            return
        }

        self.state = .loading

        resetFederatedSections(state: .loading)
        unifiedTopResults = []
        youMightLikeResults = []
        historyStore.recordSearch(query: query)

        let effectiveVideoQuery = effectiveSearchQuery(for: query, scope: .video)

        async let youtubeMusicTask = fetchYouTubeMusicSectionItems(query: query)
        async let youtubeTask = fetchYouTubeSectionItems(query: effectiveVideoQuery)
        async let tidalTask = fetchTidalSectionItems(query: query)

        let youtubeMusicResult = await youtubeMusicTask
        let youtubeResult = await youtubeTask
        let tidalResult = await tidalTask

        applyFederatedSearchResult(youtubeMusicResult, for: .youtubeMusic)
        applyFederatedSearchResult(youtubeResult, for: .youtube)
        applyFederatedSearchResult(tidalResult, for: .tidal)
        setSectionState(.idle, for: .spotify)

        unifiedTopResults = buildUnifiedTopResults(for: query)
        youMightLikeResults = buildYouMightLikeResults(
            for: query,
            excludingIDs: Set(unifiedTopResults.map(\ .id))
        )

        let hasResults = !unifiedTopResults.isEmpty || !youMightLikeResults.isEmpty
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

    private func setSectionState(_ state: FederatedSectionState, for service: FederatedService) {
        guard let index = federatedSections.firstIndex(where: { $0.service == service }) else { return }
        federatedSections[index].state = state
        federatedSections[index].items = []
    }

    private func firstSectionErrorMessage() -> String? {
        for service in UnifiedTopResultsPolicy.services {
            guard let section = federatedSections.first(where: { $0.service == service }) else {
                continue
            }

            if case .error(let message) = section.state {
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

    private func buildUnifiedTopResults(for query: String) -> [FederatedSearchItem] {
        let candidates = UnifiedTopResultsPolicy.services.flatMap { items(for: $0) }
        guard !candidates.isEmpty else { return [] }

        let context = makeUnifiedRankingContext(for: query)
        var groupedCandidates: [String: [(item: FederatedSearchItem, score: Double)]] = [:]

        for item in candidates {
            let key = unifiedResultDedupKey(for: item)
            let score = unifiedResultScore(for: item, context: context)
            groupedCandidates[key, default: []].append((item: item, score: score))
        }

        let rankedGroups: [(item: FederatedSearchItem, score: Double)] = groupedCandidates.values.compactMap { group in
            guard let representative = group.max(by: { $0.score < $1.score }) else {
                return nil
            }

            let distinctServiceCount = Set(group.map { $0.item.service }).count
            let consensusBoost = consensusConfidenceBoost(forDistinctServiceCount: distinctServiceCount)
            return (item: representative.item, score: representative.score + consensusBoost)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return providerPriority(for: lhs.item.service) < providerPriority(for: rhs.item.service)
            }
            return lhs.score > rhs.score
        }

        return enforceServiceDiversity(
            on: rankedGroups.map { $0.item },
            limit: UnifiedTopResultsPolicy.limit,
            queryHasArtistHint: context.queryHasArtistHint
        )
    }

    private func buildYouMightLikeResults(for query: String, excludingIDs: Set<String>) -> [FederatedSearchItem] {
        let candidates = YouMightLikePolicy.services
            .flatMap { items(for: $0) }
            .filter { !excludingIDs.contains($0.id) }
        guard !candidates.isEmpty else { return [] }

        let normalizedQuery = normalizedRankingText(query)
        let anchorTitle = normalizedRankingText(unifiedTopResults.first?.title ?? "")
        let anchorArtist = normalizedRankingText(primaryArtistName(from: unifiedTopResults.first?.subtitle ?? ""))

        let ranked = candidates.enumerated().map { index, item in
            let itemTitle = normalizedRankingText(item.title)
            let itemArtist = normalizedRankingText(primaryArtistName(from: item.subtitle))

            let querySimilarity = tokenOverlapScore(itemTitle, normalizedQuery)
            let anchorSimilarity = max(
                tokenOverlapScore(itemTitle, anchorTitle),
                tokenOverlapScore(itemArtist, anchorArtist)
            )
            let serviceBoost = item.service == .youtubeMusic ? 0.08 : 0.05
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
        .map { $0.item }

        let deduplicated = dedupeByMetadataPreservingOrder(ranked)
        return Array(deduplicated.prefix(YouMightLikePolicy.limit))
    }

    private func dedupeByMetadataPreservingOrder(_ items: [FederatedSearchItem]) -> [FederatedSearchItem] {
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

    private func makeUnifiedRankingContext(for query: String) -> UnifiedRankingContext {
        let normalizedQuery = normalizedRankingText(query)
        let youtubeArtistSignals = buildYouTubeArtistSignals()
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

    private func buildYouTubeArtistSignals() -> [String: Double] {
        var signals: [String: Double] = [:]

        for (index, item) in items(for: .youtube).enumerated() {
            guard case .youtubeVideo(let video) = item.payload else { continue }

            let artist = normalizedRankingText(normalizedMusicDisplayArtist(video.author, title: video.title))
            guard !artist.isEmpty else { continue }

            let viewCount = parseYouTubeViewCount(video.viewCount)
            let positionWeight = max(0.30, 1.0 - (Double(index) * 0.16))
            let viewWeight = log10(max(10.0, viewCount + 10.0))
            let totalWeight = positionWeight + (viewWeight * 0.22)

            signals[artist, default: 0] += totalWeight
        }

        for (index, item) in items(for: .youtubeMusic).enumerated() {
            let artist = normalizedRankingText(primaryArtistName(from: item.subtitle))
            guard !artist.isEmpty else { continue }

            let weight = max(0.20, 0.55 - (Double(index) * 0.10))
            signals[artist, default: 0] += weight
        }

        return signals
    }

    private func queryContainsArtistHint(_ normalizedQuery: String, candidateArtists: [String]) -> Bool {
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

    private func unifiedResultScore(for item: FederatedSearchItem, context: UnifiedRankingContext) -> Double {
        let searchableText = normalizedRankingText("\(item.title) \(primaryArtistName(from: item.subtitle))")
        let queryTokens = tokenSet(from: context.normalizedQuery)
        let itemTokens = tokenSet(from: searchableText)

        let overlap: Double
        if queryTokens.isEmpty {
            overlap = 0
        } else {
            overlap = Double(queryTokens.intersection(itemTokens).count) / Double(queryTokens.count)
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

        return (0.68 * overlap)
            + containsBoost
            + prefixBoost
            + providerBoost
            + qualityBoost
            + playabilityBoost
            + artistBoost
    }

    private func itemArtistAlignmentScore(for item: FederatedSearchItem, dominantArtist: String?) -> Double {
        guard let dominantArtist, !dominantArtist.isEmpty else { return 0 }
        let itemArtist = normalizedRankingText(primaryArtistName(from: item.subtitle))
        guard !itemArtist.isEmpty else { return 0 }
        return tokenOverlapScore(itemArtist, dominantArtist)
    }

    private func inferredArtistBoost(
        for service: FederatedService,
        alignment: Double,
        hasDominantArtist: Bool,
        queryHasArtistHint: Bool
    ) -> Double {
        guard hasDominantArtist else { return 0 }

        switch service {
        case .tidal:
            if queryHasArtistHint {
                if alignment >= 0.75 { return 0.20 }
                if alignment >= 0.45 { return 0.10 }
                return -0.05
            }

            if alignment >= 0.75 { return 0.12 }
            if alignment >= 0.45 { return 0.04 }
            return -0.16

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
        }
    }

    private func consensusConfidenceBoost(forDistinctServiceCount count: Int) -> Double {
        switch count {
        case 3...:
            return 0.10
        case 2:
            return 0.06
        default:
            return 0
        }
    }

    private func enforceServiceDiversity(
        on rankedItems: [FederatedSearchItem],
        limit: Int,
        queryHasArtistHint: Bool
    ) -> [FederatedSearchItem] {
        guard limit > 0 else { return [] }

        var selected: [FederatedSearchItem] = []
        var selectedIDs = Set<String>()
        var serviceCounts: [FederatedService: Int] = [:]

        for item in rankedItems {
            let cap: Int
            if item.service == .tidal {
                cap = queryHasArtistHint ? (UnifiedTopResultsPolicy.maxPerService[item.service] ?? 2) : 1
            } else {
                cap = UnifiedTopResultsPolicy.maxPerService[item.service] ?? limit
            }

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

        return selected
    }

    private func unifiedResultDedupKey(for item: FederatedSearchItem) -> String {
        let title = normalizedRankingText(item.title)
        let artist = normalizedRankingText(primaryArtistName(from: item.subtitle))
        return "\(title)|\(artist)"
    }

    private func primaryArtistName(from subtitle: String) -> String {
        if let first = subtitle.split(separator: "•").first {
            let artist = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty {
                return artist
            }
        }

        return subtitle
    }

    private func normalizedRankingText(_ value: String) -> String {
        let lowercased = value.lowercased()
        let withoutPunctuation = lowercased.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )

        return withoutPunctuation
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(from value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = tokenSet(from: lhs)
        let rhsTokens = tokenSet(from: rhs)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }

        let overlapCount = Double(lhsTokens.intersection(rhsTokens).count)
        let normalizer = Double(max(lhsTokens.count, rhsTokens.count))
        return normalizer == 0 ? 0 : overlapCount / normalizer
    }

    private func parseYouTubeViewCount(_ value: String) -> Double {
        let lowered = value
            .lowercased()
            .replacingOccurrences(of: ",", with: "")

        if let compactRange = lowered.range(of: "([0-9]+(?:\\.[0-9]+)?)\\s*([kmb])", options: .regularExpression) {
            let compact = String(lowered[compactRange])
            let numericPart = compact.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            guard let number = Double(numericPart) else { return 0 }

            if compact.contains("b") { return number * 1_000_000_000 }
            if compact.contains("m") { return number * 1_000_000 }
            if compact.contains("k") { return number * 1_000 }
            return number
        }

        if let numberRange = lowered.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression),
           let number = Double(lowered[numberRange]) {
            if lowered.contains("billion") { return number * 1_000_000_000 }
            if lowered.contains("million") { return number * 1_000_000 }
            if lowered.contains("thousand") { return number * 1_000 }
            return number
        }

        return 0
    }

    private func providerPriority(for service: FederatedService) -> Int {
        switch service {
        case .tidal:
            return 0
        case .youtubeMusic:
            return 1
        case .youtube:
            return 2
        case .spotify:
            return 3
        }
    }

    private func providerConfidenceBoost(for service: FederatedService, queryHasArtistHint: Bool) -> Double {
        switch service {
        case .tidal:
            return queryHasArtistHint ? 0.08 : 0.00
        case .youtubeMusic:
            return queryHasArtistHint ? 0.03 : 0.04
        case .youtube:
            return queryHasArtistHint ? 0.02 : 0.03
        case .spotify:
            return 0
        }
    }

    private func qualityConfidenceBoost(for item: FederatedSearchItem) -> Double {
        let quality = normalizedRankingText(item.audioQualityLabel ?? "")
        let codec = normalizedRankingText(item.audioCodecLabel ?? "")

        var boost: Double = 0

        if quality.contains("hi res") {
            boost += 0.06
        } else if quality.contains("lossless") {
            boost += 0.05
        } else if quality.contains("high") {
            boost += 0.02
        }

        if codec == "flac" {
            boost += 0.02
        } else if codec == "aac" {
            boost += 0.005
        }

        return boost
    }

    private func fetchYouTubeMusicSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
        do {
            let results = try await youtube.music.search(query)
            musicResults = results
            searchCache.setMusicResults(results, for: query)
            searchCacheHintStore.recordMusicResults(query: query, results: results)

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

    private func fetchYouTubeSectionItems(query: String) async -> Result<[FederatedSearchItem], Error> {
        do {
            let continuation = try await youtube.main.search(query)
            resetVideoPagination()
            updateVideoResults(with: continuation, appending: false)
            searchCache.setVideoResults(videoResults, for: query)
            searchCacheHintStore.recordVideoResults(query: query, results: videoResults)

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
                    isExplicit: false,
                    audioQualityLabel: tidalSearchQualityBadgeLabel(from: track.audioQuality),
                    audioCodecLabel: tidalSearchCodecBadgeLabel(from: track.audioQuality),
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

            let items: [FederatedSearchItem] = topTracks.map { track in
                let codecLabel = inferCodecLabelIfKnown(from: track.previewURL)
                return FederatedSearchItem(
                    id: "spotify-\(track.id)",
                    title: track.title,
                    subtitle: "\(track.artistName) • \(track.albumName ?? "Spotify")",
                    artworkURL: track.artworkURL,
                    durationSeconds: track.durationSeconds,
                    isPlayable: track.previewURL != nil,
                    isExplicit: false,
                    audioQualityLabel: track.previewURL != nil ? "Preview" : nil,
                    audioCodecLabel: codecLabel,
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

    private func inferCodecLabelIfKnown(from url: URL?) -> String? {
        guard let url else { return nil }
        let label = inferCodecLabel(from: url)
        return label == "Unknown" ? nil : label
    }

    private func tidalSearchQualityBadgeLabel(from rawValue: String?) -> String? {
        guard let quality = normalizedTidalQualityToken(from: rawValue) else {
            return nil
        }

        switch quality {
        case "HI_RES_LOSSLESS", "HI_RES":
            return "Hi-Res"
        case "LOSSLESS":
            return "Lossless"
        case "HIGH":
            return "High"
        case "MEDIUM":
            return "Medium"
        case "LOW":
            return "Low"
        case "DOLBY_ATMOS":
            return "Dolby Atmos"
        case "SONY_360RA", "360RA":
            return "360 Reality Audio"
        default:
            return nil
        }
    }

    private func tidalSearchCodecBadgeLabel(from rawValue: String?) -> String? {
        guard let quality = normalizedTidalQualityToken(from: rawValue) else {
            return nil
        }

        switch quality {
        case "HI_RES_LOSSLESS", "HI_RES", "LOSSLESS":
            return "FLAC"
        case "HIGH", "MEDIUM", "LOW":
            return "AAC"
        default:
            return nil
        }
    }

    private func normalizedTidalQualityToken(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
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
        historyStore.recordSearch(query: cleaned)
        Task { await executeSearch() }
    }

    public func recordSuccessfulPlayFromCurrentQuery() {
        historyStore.recordSuccessfulPlay(query: searchText)
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
            searchCacheHintStore.recordMusicResults(query: query, results: results)
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
            searchCacheHintStore.recordVideoResults(query: query, results: mapped)
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
                async let youtubeSuggestionsTask = youtube.main.getSearchSuggestions(query: query)
                async let musicSuggestionsTask = youtube.music.getSearchSuggestions(query: query)

                let youtubeSuggestions = (try? await youtubeSuggestionsTask) ?? []
                let musicSuggestions = (try? await musicSuggestionsTask) ?? []
                var seenSuggestionKeys = Set<String>()
                remote = (youtubeSuggestions + musicSuggestions).filter { suggestion in
                    let key = suggestion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !key.isEmpty else { return false }
                    return seenSuggestionKeys.insert(key).inserted
                }
            }

            let local = historyStore.topCandidates(prefix: query, limit: 20)
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
            suggestions = historyStore.topCandidates(prefix: query, limit: 8).map { $0.query }
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
                    searchCacheHintStore.recordMusicResults(query: normalizedTop, results: results)
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
                    searchCacheHintStore.recordVideoResults(query: normalizedTop, results: mapped)
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
    let isExplicit: Bool
    let audioQualityLabel: String?
    let audioCodecLabel: String?
    let payload: FederatedSearchPayload

    var service: FederatedService {
        switch payload {
        case .youtubeVideo:
            return .youtube
        case .youtubeMusic:
            return .youtubeMusic
        case .tidal:
            return .tidal
        case .spotify:
            return .spotify
        }
    }
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
