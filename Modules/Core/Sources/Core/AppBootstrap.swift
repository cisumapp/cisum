//
//  AppBootstrap.swift
//  cisum
//
//  Created by Aarav Gupta on 28/03/26.
//

import Aesthetics
import Authentication
import Caching
import ClerkKit
import Foundation
import Library
import Models
import Networking
import Player
import Playlists
import Plugins
import Profile
import Radio
import Search
import SwiftData
import Utilities
import YouTubeSDK

private let lifecycleSP = CisumSignpost.lifecycle

@MainActor
enum AppBootstrap {
    static func makeDependenciesOrFallback(youtube: YouTube, router: Router) -> ServicesContainer {
        let spid = lifecycleSP.begin("app-bootstrap")
        PerfLog.info("Bootstrap started")
        // FORCE IN-MEMORY FOR DIAGNOSTICS
        // return makeInMemoryDependencies(youtube: youtube, router: router, underlyingError: NSError(domain: "ManualBypass", code: 0))

        do {
            let container = try makeDependencies(youtube: youtube, router: router)
            lifecycleSP.end("app-bootstrap", state: spid, "path=persistent")
            PerfLog.info("Bootstrap complete (persistent store)")
            return container
        } catch {
            PerfLog.error("Bootstrap persistent store error: \(error.localizedDescription)")
            lifecycleSP.event("bootstrap-fallback", "error=\(error.localizedDescription)")
            // assertionFailure("Persistent bootstrap failed: \(error.localizedDescription). Falling back to in-memory dependencies.")
            let container = makeInMemoryDependencies(youtube: youtube, router: router, underlyingError: error)
            lifecycleSP.end("app-bootstrap", state: spid, "path=in-memory")
            PerfLog.warning("Bootstrap complete (in-memory fallback)")
            return container
        }
    }

    static func makeDependencies(youtube: YouTube, router: Router) throws -> ServicesContainer {
        let spid = lifecycleSP.begin("make-persistent-container")
        let modelContainer = try makePersistentModelContainer()
        lifecycleSP.end("make-persistent-container", state: spid)
        return buildDependencies(youtube: youtube, router: router, modelContainer: modelContainer)
    }

    private static func buildDependencies(
        youtube: YouTube,
        router: Router,
        modelContainer: ModelContainer
    ) -> ServicesContainer {
        let spid = lifecycleSP.begin("build-services")
        defer { lifecycleSP.end("build-services", state: spid) }

        // Initialize Clerk with publishable key
        Clerk.configure(publishableKey: "pk_live_Y2xlcmsuY2lzdW0uc3R1ZGlvJA")

        let prefetchSettings = PrefetchSettings.shared
        let networkMonitor = NetworkPathMonitor.shared
        let playbackControlSettings = PlaybackControlSettings.shared
        let streamingProviderSettings = StreamingProviderSettings.shared
        let modelContext = ModelContext(modelContainer)
        let historyStore = SearchHistoryStore(modelContainer: modelContainer)
        let mediaCacheStore = MediaCacheStore(modelContainer: modelContainer)
        let searchCacheHintStore = SearchCacheHintStore(modelContainer: modelContainer)
        let playlistLibraryStore = PlaylistLibraryStore(modelContainer: modelContainer)
        let playlistImportJobStore = PlaylistImportJobStore(modelContainer: modelContainer)
        let centralMediaStore = CentralMediaStore(modelContainer: modelContainer)
        let artworkVideoProcessor = ArtworkVideoProcessor.shared
        let metadataCache = VideoMetadataCache.shared
        let providerSDK = Plugins.makeProviderSDK()
        let includeProviderSDK = UserDefaults.standard.object(forKey: "plugins.provider_sdk_enabled") as? Bool ?? true
        let includeYouTubeFallback = UserDefaults.standard.object(forKey: "plugins.youtube_fallback_enabled") as? Bool ?? true

        Plugins.configurePlaybackURLResolver(
            providerSDK: providerSDK,
            youtube: youtube,
            mediaCacheStore: mediaCacheStore,
            metadataCache: metadataCache,
            includeProviderSDK: includeProviderSDK,
            includeYouTubeFallback: includeYouTubeFallback
        )
        let searchCache = SearchResultsCache.shared
        let radioSessionStore = RadioSessionStore.shared
        let playbackMetricsStore = PlaybackMetricsStore.shared
        let lastFMSettings = LastFMSettings.shared
        let authService = AuthService()
        let supabaseService = SupabaseService()
        let analyticsService = AnalyticsService()
        let lastFMScrobbler = LastFMScrobbler(configuration: lastFMSettings.configuration, authService: authService)
        let listeningHistoryStore = ListeningHistoryStore(modelContainer: modelContainer)
        let spotifySessionCoordinator = SpotifySessionCoordinator.shared
        let spotifyCacheStore = SpotifyCacheStore(modelContainer: modelContainer)
        spotifySessionCoordinator.setCacheDelegate(spotifyCacheStore)
        #if os(iOS)
        let artworkColorExtractor = ImageColorExtractor.shared
        #endif
        let playerPresentationController = PlayerPresentationController()
        let searchOverlayController = SearchOverlayController()
        let coreServices = CoreServices(
            prefetchSettings: prefetchSettings,
            networkMonitor: networkMonitor
        )
        let providerServices = ProviderServices(
            youtube: youtube,
            streamingProviderSettings: streamingProviderSettings
        )

        Task { @MainActor in
            await ProviderManifestStore.shared.reconcilePersistedManifests()
        }

        Task { @MainActor in
            await mediaCacheStore.performMaintenance()
            await searchCacheHintStore.performMaintenance()
            await spotifySessionCoordinator.restoreSessionIfNeeded()
//            await youtube.restoreSession()
        }

        #if os(iOS)
        let playerViewModel = PlayerViewModel(
            youtube: youtube,
            settings: prefetchSettings,
            artworkVideoProcessor: artworkVideoProcessor,
            metadataCache: metadataCache,
            mediaCacheStore: mediaCacheStore,
            playbackMetricsStore: playbackMetricsStore,
            radioSessionStore: radioSessionStore,
            scrobbleTrack: { state, playedAt in
                let duration = state.durationHint.map { Double($0) } ?? 0
                let item = LastFMPlaybackItem(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, durationSeconds: duration > 0 ? UInt(duration) : nil)
                try await lastFMScrobbler.scrobble(item, playedAt: playedAt)
            },
            recordNowPlayingTrack: { state in
                let duration = state.durationHint.map { Double($0) } ?? 0
                let item = LastFMPlaybackItem(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, durationSeconds: duration > 0 ? UInt(duration) : nil)
                try await lastFMScrobbler.recordNowPlaying(item)
            },
            isScrobblingEnabled: { lastFMSettings.enabled },
            isLocalHistoryEnabled: { lastFMSettings.localHistoryEnabled },
            startListeningSession: { state in
                await listeningHistoryStore.startSession(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, streamingService: state.streamingService.rawValue)
            },
            finishListeningSession: { sessionID, endedAt, listenedSeconds, wasScrobbled, scrobbledAt in
                Task {
                    await listeningHistoryStore.finishSession(id: sessionID, endedAt: endedAt, listenedSeconds: listenedSeconds, wasScrobbled: wasScrobbled, scrobbledAt: scrobbledAt)
                }
            },
            markScrobbledSession: { sessionID, scrobbledAt in
                Task {
                    await listeningHistoryStore.markScrobbled(id: sessionID, scrobbledAt: scrobbledAt)
                }
            },
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
            radioSessionStore: radioSessionStore,
            scrobbleTrack: { state, playedAt in
                let duration = state.durationHint.map { Double($0) } ?? 0
                let item = LastFMPlaybackItem(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, durationSeconds: duration > 0 ? UInt(duration) : nil)
                try await lastFMScrobbler.scrobble(item, playedAt: playedAt)
            },
            recordNowPlayingTrack: { state in
                let duration = state.durationHint.map { Double($0) } ?? 0
                let item = LastFMPlaybackItem(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, durationSeconds: duration > 0 ? UInt(duration) : nil)
                try await lastFMScrobbler.recordNowPlaying(item)
            },
            isScrobblingEnabled: { lastFMSettings.enabled },
            isLocalHistoryEnabled: { lastFMSettings.localHistoryEnabled },
            startListeningSession: { state in
                await listeningHistoryStore.startSession(mediaID: state.mediaID, title: state.title, artist: state.artist, album: state.albumName, artworkURL: state.artworkURL, streamingService: state.streamingService.rawValue)
            },
            finishListeningSession: { sessionID, endedAt, listenedSeconds, wasScrobbled, scrobbledAt in
                Task {
                    await listeningHistoryStore.finishSession(id: sessionID, endedAt: endedAt, listenedSeconds: listenedSeconds, wasScrobbled: wasScrobbled, scrobbledAt: scrobbledAt)
                }
            },
            markScrobbledSession: { sessionID, scrobbledAt in
                Task {
                    await listeningHistoryStore.markScrobbled(id: sessionID, scrobbledAt: scrobbledAt)
                }
            }
        )
        #endif

        let searchViewModel = SearchViewModel(
            youtube: youtube,
            settings: prefetchSettings,
            networkMonitor: networkMonitor,
            historyStore: historyStore,
            searchCacheHintStore: searchCacheHintStore,
            streamingProviderSettings: streamingProviderSettings,
            centralMediaStore: centralMediaStore,
            metadataCache: metadataCache,
            searchCache: searchCache,
            providerSDK: providerSDK // H-1: wire up all streaming providers for unified search
        )

        let playbackServices = PlaybackServices(
            playbackControlSettings: playbackControlSettings,
            playbackMetricsStore: playbackMetricsStore,
            lastFMSettings: lastFMSettings,
            lastFMScrobbler: lastFMScrobbler,
            listeningHistoryStore: listeningHistoryStore,
            streamingProviderSettings: streamingProviderSettings,
            radioSessionStore: radioSessionStore,
            artworkVideoProcessor: artworkVideoProcessor,
            playerViewModel: playerViewModel
        )

        let searchServices = SearchServices(
            historyStore: historyStore,
            searchCacheHintStore: searchCacheHintStore,
            searchCache: searchCache,
            suggestionRanker: SuggestionRanker.self,
            networkMonitor: networkMonitor,
            prefetchSettings: prefetchSettings,
            searchViewModel: searchViewModel
        )

        let libraryServices = LibraryServices(
            playlistLibraryStore: playlistLibraryStore,
            playlistImportJobStore: playlistImportJobStore,
            centralMediaStore: centralMediaStore,
            mediaCacheStore: mediaCacheStore,
            metadataCache: metadataCache
        )

        let userServices = UserServices(
            spotifySessionCoordinator: spotifySessionCoordinator,
            authService: authService,
            supabaseService: supabaseService,
            analyticsService: analyticsService
        )

        let appServices = AppServices(
            router: router,
            modelContainer: modelContainer,
            playerPresentationController: playerPresentationController,
            searchOverlayController: searchOverlayController
        )

        return ServicesContainer(
            coreServices: coreServices,
            playbackServices: playbackServices,
            searchServices: searchServices,
            libraryServices: libraryServices,
            userServices: userServices,
            providerServices: providerServices,
            appServices: appServices
        )
    }

    private static func makeInMemoryDependencies(youtube: YouTube, router: Router, underlyingError: Error) -> ServicesContainer {
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
        let schema = Schema([
            SearchHistoryEntry.self,
            ListeningHistoryEntry.self,
            MediaCacheEntry.self,
            SearchCacheHintEntry.self,
            SpotifyCacheEntry.self,
            Playlist.self,
            PlaylistItem.self,
            PlaylistImportJobEntry.self,
            PlaylistImportTrackEntry.self,
            PlaylistImportCandidateEntry.self,
            Artist.self,
            Album.self,
            Song.self,
            QueueStateEntry.self,
        ])

        // Ensure Application Support directory exists
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        // Fallback to default configuration
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: false)])
    }

    private static func makeModelContainer(configuration: ModelConfiguration? = nil) throws -> ModelContainer {
        let schema = Schema([
            SearchHistoryEntry.self,
            ListeningHistoryEntry.self,
            MediaCacheEntry.self,
            SearchCacheHintEntry.self,
            SpotifyCacheEntry.self,
            Playlist.self,
            PlaylistItem.self,
            PlaylistImportJobEntry.self,
            PlaylistImportTrackEntry.self,
            PlaylistImportCandidateEntry.self,
            Artist.self,
            Album.self,
            Song.self,
            QueueStateEntry.self,
        ])

        if let configuration {
            return try ModelContainer(for: schema, configurations: configuration)
        }

        return try ModelContainer(for: schema)
    }
}
