import Aesthetics
import Albums
import Artists
import Authentication
import Caching
import Discover
import Home
import Library
import Models
import Networking
import Player
import Playlists
import Plugins
import Profile
import Search
import SwiftData
import SwiftUI
import Utilities
import YouTubeSDK

@MainActor
public final class cisumModule {
    // MARK: - Feature Modules

    let home: HomeModule
    let discover: DiscoverModule
    let library: LibraryModule
    let player: PlayerModule
    let search: SearchModule
    let profile: ProfileModule

    // MARK: - Dependencies

    public let navigationState: NavigationState
    private let appRouter: AppRouter
    public let container: ServicesContainer

    public var router: Router {
        appRouter
    }

    public var modelContainer: ModelContainer {
        container.appServices.modelContainer
    }

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        player.handleScenePhaseChange(phase)

        if phase != .active {
            container.coreServices.prefetchSettings.flushPendingWrites()
            container.playbackServices.playbackControlSettings.flushPendingWrites()
        }
    }

    public func handleIncomingURL(_ url: URL) {
        Task {
            do {
                _ = try await ProviderManifestStore.shared.importManifest(from: url)
            } catch {
                PerfLog.debug("Failed to import provider manifest: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Neutral Facades

    public var homeView: some View {
        home.view
    }

    public var discoverView: some View {
        discover.view
    }

    public var libraryView: some View {
        library.view
    }

    public var searchView: some View {
        search.view
    }

    public var settingsView: some View {
        profile.settingsView
    }

    public var pluginsView: some View {
        PluginsView()
            .environment(container)
            .environment(container.playbackServices.streamingProviderSettings)
            .environment(ProviderManifestStore.shared)
    }

    public var profileView: some View {
        profile.profileView
    }

    public var loginView: some View {
        let authService = container.userServices.authService
        let supabaseService = container.userServices.supabaseService
        let analyticsService = container.userServices.analyticsService
        let view = LoginView { isSignup in
            guard let user = authService.user else { return }
            do {
                try await supabaseService.syncUserFromClerk(
                    clerkUserId: user.id,
                    email: user.emailAddresses.first?.emailAddress,
                    fullName: user.fullName,
                    username: user.username,
                    imageUrl: user.imageUrl
                )
            } catch {
                PerfLog.debug("Failed to sync: \(error.localizedDescription)")
            }
            analyticsService.identify(userId: user.id, properties: [
                "email": user.emailAddresses.first?.emailAddress ?? "",
                "name": user.fullName,
                "signup": isSignup,
            ])
            analyticsService.captureEvent(
                isSignup ? "user_signed_up" : "user_signed_in",
                properties: ["email": user.emailAddresses.first?.emailAddress ?? ""]
            )
        }
        return view.environment(authService)
    }

    public var spotifyLoginView: some View {
        #if canImport(SpotifySDK)
        SpotifyLoginView(coordinator: container.userServices.spotifySessionCoordinator)
        #else
        EmptyView()
        #endif
    }

    public var youtubeLoginView: some View {
        YouTubeOAuthDeviceFlowView { [weak appRouter] _ in
            Task { @MainActor in
                _ = await YouTube.shared.ensureAccessToken()
                appRouter?.pop()
            }
        } onCancel: { [weak appRouter] in
            Task { @MainActor in
                appRouter?.pop()
            }
        }
    }

    public func playlistDetailView(for id: String) -> some View {
        PlaylistDetailWrapper(playlistID: id)
    }

    public func artistDetailView(for id: String) -> some View {
        #if os(iOS)
        ArtistDetailWrapper(artistID: id)
        #else
        EmptyView()
        #endif
    }

    public func albumDetailView(for id: String) -> some View {
        #if os(iOS)
        AlbumDetailWrapper(albumID: id)
        #else
        EmptyView()
        #endif
    }

    public var searchText: Binding<String> {
        search.searchText
    }

    public func performSearch() {
        search.performSearch()
    }

    public var playerAccentColor: Color {
        player.accentColor
    }

    public var currentVideoId: String? {
        player.currentVideoId
    }

    public var playerViewModel: any PlayerViewModelInterface {
        container.playbackServices.playerViewModel
    }

    public func miniPlayer(isExpanded: Binding<Bool>, namespace: Namespace.ID) -> some View {
        player.miniPlayer(isExpanded: isExpanded, namespace: namespace)
    }

    public func expandablePlayer(show: Binding<Bool>, isExpanded: Binding<Bool>, collapsedFrame: CGRect) -> some View {
        player.expandablePlayer(show: show, isExpanded: isExpanded, collapsedFrame: collapsedFrame)
    }

    #if os(iOS) || os(macOS)
    public var systemVolumeController: SystemVolumeController {
        SystemVolumeController.shared
    }
    #endif

    // MARK: - Root View

    public func applyEnvironment(to view: some View) -> some View {
        view
            .overlay(alignment: .top) {
                ImportProgressToastView(
                    facade: container.libraryServices.importProgressFacade,
                    manager: container.libraryServices.importDownloadManager
                )
            }
            .environment(\.importDownloadManager, container.libraryServices.importDownloadManager)
            .environment(\.importProgressFacade, container.libraryServices.importProgressFacade)
            .environment(container)
            .environment(container.coreServices)
            .environment(container.playbackServices)
            .environment(container.searchServices)
            .environment(container.libraryServices)
            .environment(\.playlistLibraryStore, container.libraryServices.playlistLibraryStore)
            .environment(\.centralMediaStore, container.libraryServices.centralMediaStore)
            .environment(container.userServices)
            .environment(container.providerServices)
            .environment(container.appServices)
            .environment(container.appServices.playerPresentationController)
            .environment(container.appServices.searchOverlayController)
            .environment(\.playerViewModel, container.playbackServices.playerViewModel)
            .environment(\.searchViewModel, container.searchServices.searchViewModel)
            .environment(container.userServices.authService)
            .environment(container.userServices.spotifySessionCoordinator)
            .environment(container.userServices.supabaseService)
            .environment(container.userServices.analyticsService)
            .environment(container.playbackServices.lastFMSettings)
            .environment(\.lastFMScrobbler, container.playbackServices.lastFMScrobbler)
            .environment(container.playbackServices.streamingProviderSettings)
            .modelContainer(modelContainer)
    }

    @ViewBuilder
    public var rootView: some View {
        let authService = container.userServices.authService
        if authService.isAuthenticated || authService.isGuestMode {
            Aesthetics.RootView(playerOverlayState: .init()) {
                self.applyEnvironment(to: RootView(module: self))
            } overlayWrapper: { overlay in
                AnyView(self.applyEnvironment(to: overlay))
            }
        } else {
            loginView
        }
    }

    // MARK: - Init

    public init() {
        let navigationState = NavigationState()
        let appRouter = AppRouter()

        appRouter.onTabSwitch = { [weak navigationState] tab in
            navigationState?.selectedTab = tab
        }

        appRouter.onPush = { [weak navigationState] route in
            guard let state = navigationState else { return }
            var path = state.tabPaths[state.selectedTab] ?? NavigationPath()
            path.append(route)
            state.tabPaths[state.selectedTab] = path
        }

        appRouter.onPop = { [weak navigationState] in
            guard let state = navigationState else { return }
            var path = state.tabPaths[state.selectedTab] ?? NavigationPath()
            if !path.isEmpty {
                path.removeLast()
                state.tabPaths[state.selectedTab] = path
            }
        }

        self.navigationState = navigationState
        self.appRouter = appRouter

        YouTubeSDKConfig.storage = KeychainYouTubeStorage()
        let youtube = YouTube.shared
        let container = AppBootstrap.makeDependenciesOrFallback(youtube: youtube, router: appRouter)
        self.container = container

        // Initialize Features
        self.home = HomeModule(youtube: youtube)
        self.discover = DiscoverModule()
        self.library = LibraryModule()

        self.player = PlayerModule(
            dependencies: PlayerDependencies(viewModel: container.playbackServices.playerViewModel)
        )

        self.profile = ProfileModule(
            prefetchSettings: container.coreServices.prefetchSettings,
            networkMonitor: container.coreServices.networkMonitor,
            playbackControlSettings: container.playbackServices.playbackControlSettings,
            streamingProviderSettings: container.playbackServices.streamingProviderSettings,
            lastFMSettings: container.playbackServices.lastFMSettings
        )

        self.search = SearchModule(
            dependencies: SearchDependencies(
                youtube: container.providerServices.youtube,
                settings: container.coreServices.prefetchSettings,
                networkMonitor: container.coreServices.networkMonitor,
                historyStore: container.searchServices.historyStore,
                searchCacheHintStore: container.searchServices.searchCacheHintStore,
                streamingProviderSettings: container.playbackServices.streamingProviderSettings,
                centralMediaStore: container.libraryServices.centralMediaStore,
                metadataCache: container.libraryServices.metadataCache,
                searchCache: container.searchServices.searchCache,
                spotifySessionCoordinator: container.userServices.spotifySessionCoordinator,
                viewModel: container.searchServices.searchViewModel
            )
        )
    }
}
