//
import ProviderSDK

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

#if os(iOS)
import BackgroundTasks
#endif

private let lifecycleSP = CisumSignpost.lifecycle

@MainActor
enum AppBootstrap {
    nonisolated static let spotifyRefreshTaskID = "studio.cisum.spotify.refresh"

    /// Register the Spotify background-refresh task. Must be called during app launch (before
    /// launch completes). Best-effort: iOS schedules opportunistically — the real freshness
    /// guarantees are the on-demand + foreground/hourly headless refreshes.
    static func registerSpotifyBackgroundRefresh() {
        #if os(iOS)
        // BGTaskScheduler runs the launch handler on a PRIVATE BACKGROUND QUEUE. Route it to a
        // nonisolated function so the closure doesn't inherit this enum's @MainActor isolation
        // (which would trip Swift's executor assertion and SIGTRAP). Main-actor work hops inside.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: spotifyRefreshTaskID, using: nil) { @Sendable task in
            handleSpotifyBackgroundRefresh(task)
        }
        scheduleSpotifyBackgroundRefresh()
        #endif
    }

    #if os(iOS)
    /// Invoked by BGTaskScheduler on a background queue — MUST stay `nonisolated`.
    nonisolated static func handleSpotifyBackgroundRefresh(_ task: BGTask) {
        // ponytail: BGTask isn't Sendable, but its expirationHandler/setTaskCompleted are safe to
        // call from any queue per BGTaskScheduler's contract — rebind to cross the async boundary.
        nonisolated(unsafe) let task = task
        let work = Task { @MainActor in
            await SpotifySessionCoordinator.shared.refreshActiveSessions()
        }
        task.expirationHandler = { work.cancel() }
        Task {
            _ = await work.value
            scheduleSpotifyBackgroundRefresh()
            task.setTaskCompleted(success: true)
        }
    }
    #endif

    /// nonisolated: only touches the thread-safe BGTaskScheduler, so it's callable from any executor.
    nonisolated static func scheduleSpotifyBackgroundRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: spotifyRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // ~30 min
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    static func makeDependenciesOrFallback(youtube: YouTube, router: Router) -> ServicesContainer {
        let spid = lifecycleSP.begin("app-bootstrap")
        PerfLog.info("Bootstrap started")
        registerSpotifyBackgroundRefresh()
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
        let savedLibrary = SavedLibraryService(store: playlistLibraryStore)
        let playlistImportJobStore = PlaylistImportJobStore(modelContainer: modelContainer)
        let centralMediaStore = CentralMediaStore(modelContainer: modelContainer)
        let metadataCache = VideoMetadataCache.shared
        // Sources are built from the user's enabled plugins. Native adapters for YouTube and
        // Spotify conform to the same MusicSource protocol and join this registry once written;
        // nothing downstream will need to change when they do.
        let pluginStore = PluginStore()

        // Seeded synchronously with the native sources. Plugin loading below is async, and
        // buildDependencies returns before it finishes — a tap in that window used to find an
        // empty registry and fail with no log at all.
        let sourceRegistry = SourceRegistry(sources: [
            YouTubeMusicSource(youtube: youtube),
            YouTubeVideoSource(youtube: youtube),
        ])
        sourceRegistry.preferredSourceID = "youtube_music"

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
        ArtworkPipeline.configure()
        #endif
        let playerPresentationController = PlayerPresentationController()
        let searchOverlayController = SearchOverlayController()
        let coreServices = CoreServices(
            prefetchSettings: prefetchSettings,
            networkMonitor: networkMonitor
        )
        let providerServices = ProviderServices(
            youtube: youtube,
            streamingProviderSettings: streamingProviderSettings,
            sourceRegistry: sourceRegistry,
            pluginStore: pluginStore
        )

        Task { @MainActor in
            await pluginStore.load()

            // Native SDKs and downloaded plugins go into the same registry and are
            // indistinguishable from there on. YouTube first because it is the default playback
            // backend; the user's plugin ordering takes over once they install something.
            var sources: [any MusicSource] = [
                YouTubeMusicSource(youtube: youtube),
                YouTubeVideoSource(youtube: youtube),
            ]
            await sources.append(contentsOf: SourceBuilder.buildSources(from: pluginStore))

            sourceRegistry.replace(with: sources)
            sourceRegistry.preferredSourceID = sourceRegistry.preferredSourceID ?? "youtube_music"
        }

        Task { @MainActor in
            await mediaCacheStore.performMaintenance()
            await searchCacheHintStore.performMaintenance()
            await spotifySessionCoordinator.restoreSessionIfNeeded()
//            await youtube.restoreSession()
        }

        // One construction, both platforms. The previous version built this twice — 45 near
        // identical lines per platform, differing only in an artwork-colour argument — and passed
        // in eleven collaborators plus seven closures, because the view model implemented queueing,
        // searching, scoring, resolution, artwork, and scrobbling itself. It now coordinates
        // components that own those jobs, so it needs the source registry and nothing else.
        let player = PlayerViewModel(sources: sourceRegistry)

        // Persistence is injected rather than reached for, because Player does not import
        // SwiftData. These three closures are what make "match once, then never search again"
        // actually stick across launches.
        let songSourceStore = SongSourceStore(modelContainer: modelContainer)
        player.configurePersistence(
            lookup: { songSourceStore.lookup($0) },
            persist: { songSourceStore.persist($0, track: $1, stream: $2) },
            invalidate: { songSourceStore.invalidate($0) }
        )

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
            sourceRegistry: sourceRegistry
        )

        let playbackServices = PlaybackServices(
            playbackControlSettings: playbackControlSettings,
            playbackMetricsStore: playbackMetricsStore,
            lastFMSettings: lastFMSettings,
            lastFMScrobbler: lastFMScrobbler,
            listeningHistoryStore: listeningHistoryStore,
            streamingProviderSettings: streamingProviderSettings,
            radioSessionStore: radioSessionStore,
            player: player
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

        let importProgressFacade = ImportProgressFacade()
        let importServices = ImportServicesFactory.make(
            youtube: youtube,
            spotifyCoordinator: spotifySessionCoordinator
        )
        let importDownloadManager = ImportDownloadManager(
            jobStore: playlistImportJobStore,
            centralMediaStore: centralMediaStore,
            playlistLibraryStore: playlistLibraryStore,
            services: importServices,
            progress: importProgressFacade
        )
        Task { await importDownloadManager.resumePendingJobs() }

        let libraryServices = LibraryServices(
            playlistLibraryStore: playlistLibraryStore,
            savedLibrary: savedLibrary,
            playlistImportJobStore: playlistImportJobStore,
            centralMediaStore: centralMediaStore,
            mediaCacheStore: mediaCacheStore,
            metadataCache: metadataCache,
            importDownloadManager: importDownloadManager,
            importProgressFacade: importProgressFacade
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
