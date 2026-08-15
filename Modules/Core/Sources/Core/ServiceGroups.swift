import Authentication
import Caching
import Foundation
import Library
import Models
import Networking
import Observation
import Player
import Playlists
import Plugins
import Profile
import Radio
import Search
import SwiftData
import Utilities
import YouTubeSDK

@Observable
@MainActor
public final class CoreServices {
    public let prefetchSettings: PrefetchSettings
    public let networkMonitor: NetworkPathMonitor

    public init(
        prefetchSettings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor
    ) {
        self.prefetchSettings = prefetchSettings
        self.networkMonitor = networkMonitor
    }
}

@Observable
@MainActor
public final class PlaybackServices {
    public let playbackControlSettings: PlaybackControlSettings
    public let playbackMetricsStore: PlaybackMetricsStore
    public let lastFMSettings: LastFMSettings
    public let lastFMScrobbler: LastFMScrobbler
    public let listeningHistoryStore: ListeningHistoryStore
    public let streamingProviderSettings: StreamingProviderSettings
    public let radioSessionStore: RadioSessionStore
    // ArtworkVideoProcessor (729 LOC of FFmpeg) left Player during the architecture reset —
    // generating animated artwork is not a playback concern. The code is preserved at
    // .reset-reference/Player-Sources/ for when animated artwork is rebuilt as its own module.

    /// The concrete player. Held so `PlayerModule` can be built from it and so the state objects
    /// below have a single owner.
    public let player: PlayerViewModel

    /// Commands, exposed as the protocol so callers cannot reach into player internals.
    public var playbackCommands: any PlaybackCommands {
        player
    }

    /// The four published state objects, split by update frequency. They are surfaced individually
    /// rather than through `player` so each view can take only the one it reads — see
    /// Models/Playback/PlayerState.swift for why that matters.
    public var nowPlayingState: NowPlayingState {
        player.nowPlaying
    }

    public var transportState: TransportState {
        player.transport
    }

    public var progressState: ProgressState {
        player.progress
    }

    public var lyricsPresentation: LyricsPresentation {
        player.lyrics
    }

    public init(
        playbackControlSettings: PlaybackControlSettings,
        playbackMetricsStore: PlaybackMetricsStore,
        lastFMSettings: LastFMSettings,
        lastFMScrobbler: LastFMScrobbler,
        listeningHistoryStore: ListeningHistoryStore,
        streamingProviderSettings: StreamingProviderSettings,
        radioSessionStore: RadioSessionStore,
        player: PlayerViewModel
    ) {
        self.playbackControlSettings = playbackControlSettings
        self.playbackMetricsStore = playbackMetricsStore
        self.lastFMSettings = lastFMSettings
        self.lastFMScrobbler = lastFMScrobbler
        self.listeningHistoryStore = listeningHistoryStore
        self.streamingProviderSettings = streamingProviderSettings
        self.radioSessionStore = radioSessionStore
        self.player = player
    }
}

@Observable
@MainActor
public final class SearchServices {
    public let historyStore: Search.SearchHistoryStore
    public let searchCacheHintStore: SearchCacheHintStore
    public let searchCache: any SearchResultsCaching
    public let suggestionRanker: SuggestionRanker.Type
    public let networkMonitor: NetworkPathMonitor
    public let prefetchSettings: PrefetchSettings
    public let searchViewModel: any SearchViewModelInterface

    public init(
        historyStore: Search.SearchHistoryStore,
        searchCacheHintStore: SearchCacheHintStore,
        searchCache: any SearchResultsCaching,
        suggestionRanker: SuggestionRanker.Type,
        networkMonitor: NetworkPathMonitor,
        prefetchSettings: PrefetchSettings,
        searchViewModel: any SearchViewModelInterface
    ) {
        self.historyStore = historyStore
        self.searchCacheHintStore = searchCacheHintStore
        self.searchCache = searchCache
        self.suggestionRanker = suggestionRanker
        self.networkMonitor = networkMonitor
        self.prefetchSettings = prefetchSettings
        self.searchViewModel = searchViewModel
    }
}

@Observable
@MainActor
public final class LibraryServices {
    public let playlistLibraryStore: PlaylistLibraryStore
    public let savedLibrary: SavedLibraryService
    public let playlistImportJobStore: PlaylistImportJobStore
    public let centralMediaStore: CentralMediaStore
    public let mediaCacheStore: MediaCacheStore
    public let metadataCache: any VideoMetadataCaching
    public let importDownloadManager: ImportDownloadManager
    public let importProgressFacade: ImportProgressFacade

    public init(
        playlistLibraryStore: PlaylistLibraryStore,
        savedLibrary: SavedLibraryService,
        playlistImportJobStore: PlaylistImportJobStore,
        centralMediaStore: CentralMediaStore,
        mediaCacheStore: MediaCacheStore,
        metadataCache: any VideoMetadataCaching,
        importDownloadManager: ImportDownloadManager,
        importProgressFacade: ImportProgressFacade
    ) {
        self.playlistLibraryStore = playlistLibraryStore
        self.savedLibrary = savedLibrary
        self.playlistImportJobStore = playlistImportJobStore
        self.centralMediaStore = centralMediaStore
        self.mediaCacheStore = mediaCacheStore
        self.metadataCache = metadataCache
        self.importDownloadManager = importDownloadManager
        self.importProgressFacade = importProgressFacade
    }
}

@Observable
@MainActor
public final class UserServices {
    public let spotifySessionCoordinator: SpotifySessionCoordinator
    public let authService: AuthService
    public let supabaseService: SupabaseService
    public let analyticsService: AnalyticsService

    public init(
        spotifySessionCoordinator: SpotifySessionCoordinator,
        authService: AuthService,
        supabaseService: SupabaseService,
        analyticsService: AnalyticsService
    ) {
        self.spotifySessionCoordinator = spotifySessionCoordinator
        self.authService = authService
        self.supabaseService = supabaseService
        self.analyticsService = analyticsService
    }
}

@Observable
@MainActor
public final class ProviderServices {
    public let youtube: YouTube
    public let streamingProviderSettings: StreamingProviderSettings

    /// Every music source the app can play from — native SDKs and user-installed plugins alike.
    ///
    /// Built by `AppBootstrap`. Nothing downstream knows whether a given source is a JavaScript
    /// plugin, a JSON manifest, or a hand-written Swift SDK.
    public let sourceRegistry: SourceRegistry

    /// The user's installed plugins. Owns installation, settings, and updates — never execution.
    public let pluginStore: PluginStore

    /// Source ids in the user's preferred order, best first.
    ///
    /// Views pass this to `playableRef(preferring:)` so a song plays from the user's chosen
    /// service when it exists there.
    public var preferredSourceIDs: [String] {
        let ordered = sourceRegistry.playable.map(\.id)
        guard let preferred = sourceRegistry.preferredSourceID else { return ordered }
        return [preferred] + ordered.filter { $0 != preferred }
    }

    public init(
        youtube: YouTube,
        streamingProviderSettings: StreamingProviderSettings,
        sourceRegistry: SourceRegistry,
        pluginStore: PluginStore
    ) {
        self.youtube = youtube
        self.streamingProviderSettings = streamingProviderSettings
        self.sourceRegistry = sourceRegistry
        self.pluginStore = pluginStore
    }
}

@Observable
@MainActor
public final class AppServices {
    public let router: Router
    public let modelContainer: ModelContainer
    public let playerPresentationController: PlayerPresentationController
    public let searchOverlayController: SearchOverlayController

    public init(
        router: Router,
        modelContainer: ModelContainer,
        playerPresentationController: PlayerPresentationController,
        searchOverlayController: SearchOverlayController
    ) {
        self.router = router
        self.modelContainer = modelContainer
        self.playerPresentationController = playerPresentationController
        self.searchOverlayController = searchOverlayController
    }
}
