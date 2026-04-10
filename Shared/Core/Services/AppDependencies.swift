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
        self.playlistLibraryStore = playlistLibraryStore
        self.playlistImportJobStore = playlistImportJobStore
        self.playerViewModel = playerViewModel
        self.searchViewModel = searchViewModel
    }
}

extension AppDependencies {
    static func make(
        youtube: YouTube = .shared,
        router: Router = .shared
    ) -> AppDependencies {
        let bootstrap = AppBootstrap.makeDependenciesOrFallback(youtube: youtube)

        return AppDependencies(
            youtube: youtube,
            router: router,
            modelContainer: bootstrap.modelContainer,
            prefetchSettings: bootstrap.prefetchSettings,
            networkMonitor: bootstrap.networkMonitor,
            playlistLibraryStore: bootstrap.playlistLibraryStore,
            playlistImportJobStore: bootstrap.playlistImportJobStore,
            playerViewModel: bootstrap.playerViewModel,
            searchViewModel: bootstrap.searchViewModel
        )
    }

    static func preview() -> AppDependencies {
        make(youtube: .shared, router: Router())
    }
}