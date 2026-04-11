import Observation
import SwiftData
import YouTubeSDK

@Observable
@MainActor
final class AppDependencies {
    let youtube: YouTube
    let router: Router
    let modelContainer: ModelContainer
    let prefetchSettings: PrefetchSettings
    let networkMonitor: NetworkPathMonitor
    let playbackControlSettings: PlaybackControlSettings
    let streamingProviderSettings: StreamingProviderSettings
    let playlistLibraryStore: PlaylistLibraryStore
    let playlistImportJobStore: PlaylistImportJobStore
    let playerViewModel: PlayerViewModel
    let searchViewModel: SearchViewModel

    init(
        youtube: YouTube,
        router: Router,
        modelContainer: ModelContainer,
        prefetchSettings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor,
        playbackControlSettings: PlaybackControlSettings,
        streamingProviderSettings: StreamingProviderSettings,
        playlistLibraryStore: PlaylistLibraryStore,
        playlistImportJobStore: PlaylistImportJobStore,
        playerViewModel: PlayerViewModel,
        searchViewModel: SearchViewModel
    ) {
        self.youtube = youtube
        self.router = router
        self.modelContainer = modelContainer
        self.prefetchSettings = prefetchSettings
        self.networkMonitor = networkMonitor
        self.playbackControlSettings = playbackControlSettings
        self.streamingProviderSettings = streamingProviderSettings
        self.playlistLibraryStore = playlistLibraryStore
        self.playlistImportJobStore = playlistImportJobStore
        self.playerViewModel = playerViewModel
        self.searchViewModel = searchViewModel
    }
}

extension AppDependencies {
    static func make(
        youtube: YouTube = YouTube(),
        router: Router = Router()
    ) -> AppDependencies {
        AppBootstrap.makeDependenciesOrFallback(youtube: youtube, router: router)
    }

    static func preview() -> AppDependencies {
        make()
    }
}
