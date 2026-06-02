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
    private let coreDomain: CoreInterface
    private let playbackDomain: PlaybackInterface
    private let searchDomain: SearchInterface
    private let libraryDomain: LibraryInterface
    private let userDomain: UserInterface
    private let appDomain: AppInterface

    public var router: Router {
        appRouter
    }

    public var modelContainer: ModelContainer {
        appDomain.modelContainer
    }

    public func handleScenePhaseChange(_ phase: ScenePhase) {
        player.handleScenePhaseChange(phase)

        if phase != .active {
            coreDomain.prefetchSettings.flushPendingWrites()
            playbackDomain.playbackControlSettings.flushPendingWrites()
        }
    }

    public func handleIncomingURL(_ url: URL) {
        Task {
            do {
                _ = try await ProviderManifestStore.shared.importManifest(from: url)
            } catch {
                print("Failed to import provider manifest: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Neutral Facades

    public var homeView: AnyView {
        AnyView(home.view)
    }

    public var discoverView: AnyView {
        AnyView(discover.view)
    }

    public var libraryView: AnyView {
        AnyView(library.view)
    }

    public var searchView: AnyView {
        AnyView(search.view)
    }

    public var settingsView: AnyView {
        AnyView(profile.settingsView)
    }

    public var pluginsView: AnyView {
        AnyView(
            PluginsView()
                .environment(container)
                .environment(container.playbackServices.streamingProviderSettings)
                .environment(ProviderManifestStore.shared)
        )
    }

    public var profileView: AnyView {
        AnyView(profile.profileView)
    }

    public var loginView: AnyView {
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
                print("Failed to sync: \(error.localizedDescription)")
            }
            analyticsService.identify(userId: user.id, properties: [
                "email": user.emailAddresses.first?.emailAddress ?? "",
                "name": user.fullName,
                "signup": isSignup
            ])
            analyticsService.captureEvent(
                isSignup ? "user_signed_up" : "user_signed_in",
                properties: ["email": user.emailAddresses.first?.emailAddress ?? ""]
            )
        }
        return AnyView(view.environment(authService))
    }

    public var spotifyLoginView: AnyView {
        #if canImport(SpotifySDK)
        AnyView(SpotifyLoginView(coordinator: container.userServices.spotifySessionCoordinator))
        #else
        AnyView(EmptyView())
        #endif
    }

    public var youtubeLoginView: AnyView {
        let view = YouTubeOAuthDeviceFlowView { [weak appRouter] _ in
            Task { @MainActor in
                _ = await YouTube.shared.ensureAccessToken()
                appRouter?.pop()
            }
        } onCancel: { [weak appRouter] in
            Task { @MainActor in
                appRouter?.pop()
            }
        }
        return AnyView(view)
    }

    public func playlistDetailView(for id: String) -> AnyView {
        AnyView(PlaylistDetailWrapper(playlistID: id))
    }

    public func artistDetailView(for id: String) -> AnyView {
        #if os(iOS)
        AnyView(ArtistDetailWrapper(artistID: id))
        #else
        AnyView(EmptyView())
        #endif
    }

    public func albumDetailView(for id: String) -> AnyView {
        #if os(iOS)
        AnyView(AlbumDetailWrapper(albumID: id))
        #else
        AnyView(EmptyView())
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

    public func miniPlayer(isExpanded: Binding<Bool>, namespace: Namespace.ID) -> AnyView {
        AnyView(player.miniPlayer(isExpanded: isExpanded, namespace: namespace))
    }

    public func expandablePlayer(show: Binding<Bool>, isExpanded: Binding<Bool>, collapsedFrame: CGRect) -> AnyView {
        AnyView(player.expandablePlayer(show: show, isExpanded: isExpanded, collapsedFrame: collapsedFrame))
    }

    #if os(iOS) || os(macOS)
    public var systemVolumeController: SystemVolumeController {
        SystemVolumeController.shared
    }
    #endif

    // MARK: - Root View

    public func applyEnvironment(to view: some View) -> some View {
        view
            .environment(container)
            .environment(container.coreServices)
            .environment(container.playbackServices)
            .environment(container.searchServices)
            .environment(container.libraryServices)
            .environment(container.userServices)
            .environment(container.providerServices)
            .environment(container.appServices)
            .environment(container.app.playerPresentationController)
            .environment(container.app.searchOverlayController)
            .environment(\.playerViewModel, container.playbackServices.playerViewModel)
            .environment(\.searchViewModel, container.searchServices.searchViewModel)
            .environment(\.youtube, container.providerServices.youtube)
            .environment(container.userServices.authService)
            .environment(container.userServices.spotifySessionCoordinator)
            .environment(container.userServices.supabaseService)
            .environment(container.userServices.analyticsService)


            .environment(container.playbackServices.lastFMSettings)
            .environment(\.lastFMScrobbler, container.playbackServices.lastFMScrobbler)
            .environment(container.playbackServices.streamingProviderSettings)
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

        // 1. Store Interfaces
        self.coreDomain = container.core
        self.playbackDomain = container.playback
        self.searchDomain = container.search
        self.libraryDomain = container.library
        self.userDomain = container.user
        self.appDomain = container.app

        // 2. Initialize Features
        self.home = HomeModule(youtube: youtube)
        self.discover = DiscoverModule()
        self.library = LibraryModule()

        self.player = PlayerModule(
            dependencies: PlayerDependencies(viewModel: container.playback.playerViewModel)
        )

        self.profile = ProfileModule(
            prefetchSettings: container.core.prefetchSettings,
            networkMonitor: container.core.networkMonitor,
            playbackControlSettings: container.playback.playbackControlSettings,
            streamingProviderSettings: container.playback.streamingProviderSettings,
            lastFMSettings: container.playbackServices.lastFMSettings
        )

        self.search = SearchModule(
            dependencies: SearchDependencies(
                youtube: container.app.youtube,
                settings: container.core.prefetchSettings,
                networkMonitor: container.core.networkMonitor,
                historyStore: container.search.historyStore,
                searchCacheHintStore: container.search.searchCacheHintStore,
                streamingProviderSettings: container.playback.streamingProviderSettings,
                centralMediaStore: container.library.centralMediaStore,
                metadataCache: container.library.metadataCache,
                searchCache: container.search.searchCache,
                spotifySessionCoordinator: container.user.spotifySessionCoordinator,
                viewModel: container.search.searchViewModel
            )
        )
    }
}
