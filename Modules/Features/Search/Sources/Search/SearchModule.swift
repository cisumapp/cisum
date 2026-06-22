import Caching
import Library
import Models
import Networking
import Player
import Plugins
import SwiftUI
import YouTubeSDK

@MainActor
public struct SearchDependencies {
    public let youtube: YouTube
    public let settings: PrefetchSettings
    public let networkMonitor: NetworkPathMonitor
    public let historyStore: SearchHistoryStore
    public let searchCacheHintStore: SearchCacheHintStore
    public let streamingProviderSettings: StreamingProviderSettings
    public let centralMediaStore: CentralMediaStore?
    public let metadataCache: any VideoMetadataCaching
    public let searchCache: any SearchResultsCaching
    public let spotifySessionCoordinator: SpotifySessionCoordinator?
    public let viewModel: any SearchViewModelInterface

    public init(
        youtube: YouTube,
        settings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor,
        historyStore: SearchHistoryStore,
        searchCacheHintStore: SearchCacheHintStore,
        streamingProviderSettings: StreamingProviderSettings,
        centralMediaStore: CentralMediaStore?,
        metadataCache: any VideoMetadataCaching,
        searchCache: any SearchResultsCaching,
        spotifySessionCoordinator: SpotifySessionCoordinator?,
        viewModel: any SearchViewModelInterface
    ) {
        self.youtube = youtube
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.historyStore = historyStore
        self.searchCacheHintStore = searchCacheHintStore
        self.streamingProviderSettings = streamingProviderSettings
        self.centralMediaStore = centralMediaStore
        self.metadataCache = metadataCache
        self.searchCache = searchCache
        self.spotifySessionCoordinator = spotifySessionCoordinator
        self.viewModel = viewModel
    }
}

@MainActor
public final class SearchModule {
    private let viewModel: any SearchViewModelInterface
    private let spotifySessionCoordinator: SpotifySessionCoordinator?

    public init(dependencies: SearchDependencies) {
        self.viewModel = dependencies.viewModel
        self.spotifySessionCoordinator = dependencies.spotifySessionCoordinator
    }

    public var view: some View {
        SearchView()
    }

    public var searchText: Binding<String> {
        Binding(
            get: { self.viewModel.searchText },
            set: { self.viewModel.searchText = $0 }
        )
    }

    public func performSearch() {
        // Debounced search is handled by the view model's reactive searchText if implemented that way,
        // or we can add performSearch to the interface if needed.
    }
}
