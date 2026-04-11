//
//  AppBootstrap.swift
//  cisum
//
//  Created by Aarav Gupta on 28/03/26.
//

import Foundation
import SwiftData
import YouTubeSDK

@MainActor
enum AppBootstrap {
    static func makeDependenciesOrFallback(youtube: YouTube, router: Router) -> AppDependencies {
        do {
            return try makeDependencies(youtube: youtube, router: router)
        } catch {
            assertionFailure("Persistent bootstrap failed: \(error.localizedDescription). Falling back to in-memory dependencies.")
            return makeInMemoryDependencies(youtube: youtube, router: router, underlyingError: error)
        }
    }

    static func makeDependencies(youtube: YouTube, router: Router) throws -> AppDependencies {
        let modelContainer = try makePersistentModelContainer()
        return buildDependencies(youtube: youtube, router: router, modelContainer: modelContainer)
    }

    private static func buildDependencies(
        youtube: YouTube,
        router: Router,
        modelContainer: ModelContainer
    ) -> AppDependencies {
        let prefetchSettings = PrefetchSettings.shared
        let networkMonitor = NetworkPathMonitor.shared
        let playbackControlSettings = PlaybackControlSettings.shared
        let streamingProviderSettings = StreamingProviderSettings.shared
        let modelContext = ModelContext(modelContainer)
        let historyStore = SearchHistoryStore(context: modelContext)
        let mediaCacheStore = MediaCacheStore(context: modelContext)
        let searchCacheHintStore = SearchCacheHintStore(context: modelContext)
        let playlistLibraryStore = PlaylistLibraryStore(context: modelContext)
        let playlistImportJobStore = PlaylistImportJobStore(context: modelContext)
        let artworkVideoProcessor = ArtworkVideoProcessor.shared
        let metadataCache = VideoMetadataCache.shared
        let searchCache = SearchResultsCache.shared
        let radioSessionStore = RadioSessionStore.shared
        let playbackMetricsStore = PlaybackMetricsStore.shared
    #if os(iOS)
        let artworkColorExtractor = ArtworkDominantColorExtractor.shared
    #endif

        Task { @MainActor in
            await mediaCacheStore.performMaintenance()
            searchCacheHintStore.performMaintenance()
        }

        restoreCookies(into: youtube)

#if os(iOS)
        let playerViewModel = PlayerViewModel(
            youtube: youtube,
            settings: prefetchSettings,
            artworkVideoProcessor: artworkVideoProcessor,
            metadataCache: metadataCache,
            mediaCacheStore: mediaCacheStore,
            playbackMetricsStore: playbackMetricsStore,
            streamingProviderSettings: streamingProviderSettings,
            radioSessionStore: radioSessionStore,
            artworkColorExtractor: artworkColorExtractor
        )
#else
        let playerViewModel = PlayerViewModel(
            youtube: youtube,
            settings: prefetchSettings,
            artworkVideoProcessor: artworkVideoProcessor,
            metadataCache: metadataCache,
            mediaCacheStore: mediaCacheStore,
            playbackMetricsStore: playbackMetricsStore,
            streamingProviderSettings: streamingProviderSettings,
            radioSessionStore: radioSessionStore
        )
#endif

        return AppDependencies(
            youtube: youtube,
            router: router,
            modelContainer: modelContainer,
            prefetchSettings: prefetchSettings,
            networkMonitor: networkMonitor,
            playbackControlSettings: playbackControlSettings,
            streamingProviderSettings: streamingProviderSettings,
            playlistLibraryStore: playlistLibraryStore,
            playlistImportJobStore: playlistImportJobStore,
            playerViewModel: playerViewModel,
            searchViewModel: SearchViewModel(
                youtube: youtube,
                settings: prefetchSettings,
                networkMonitor: networkMonitor,
                historyStore: historyStore,
                searchCacheHintStore: searchCacheHintStore,
                streamingProviderSettings: streamingProviderSettings,
                metadataCache: metadataCache,
                searchCache: searchCache
            )
        )
    }

    private static func makeInMemoryDependencies(youtube: YouTube, router: Router, underlyingError: Error) -> AppDependencies {
        let modelContainer: ModelContainer
        do {
            modelContainer = try makeModelContainer(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            preconditionFailure(
                "Bootstrap failed for persistent and in-memory stores. " +
                "persistent=\(underlyingError.localizedDescription) memory=\(error.localizedDescription)"
            )
        }

        return buildDependencies(youtube: youtube, router: router, modelContainer: modelContainer)
    }

    private static func makePersistentModelContainer() throws -> ModelContainer {
        prepareSharedApplicationSupportDirectory()
        return try makeModelContainer()
    }

    private static func makeModelContainer(configuration: ModelConfiguration? = nil) throws -> ModelContainer {
        if let configuration {
            return try ModelContainer(
                for: SearchHistoryEntry.self,
                MediaCacheEntry.self,
                SearchCacheHintEntry.self,
                Playlist.self,
                PlaylistItem.self,
                PlaylistImportJobEntry.self,
                PlaylistImportTrackEntry.self,
                PlaylistImportCandidateEntry.self,
                configurations: configuration
            )
        }

        return try ModelContainer(
            for: SearchHistoryEntry.self,
            MediaCacheEntry.self,
            SearchCacheHintEntry.self,
            Playlist.self,
            PlaylistItem.self,
            PlaylistImportJobEntry.self,
            PlaylistImportTrackEntry.self,
            PlaylistImportCandidateEntry.self
        )
    }

    private static func prepareSharedApplicationSupportDirectory() {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.aaravgupta.cisum"
        ) else {
            return
        }

        let appSupportURL = groupURL.appendingPathComponent("Library/Application Support")
        do {
            try FileManager.default.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Non-fatal: if creation fails, ModelContainer will attempt recovery.
        }
    }

    private static func restoreCookies(into youtube: YouTube) {
        if let cookieString = Keychain.load(key: "user_cookies") {
            youtube.cookies = cookieString
        }
    }
}
