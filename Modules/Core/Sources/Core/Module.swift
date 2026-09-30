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

#if canImport(SpotifySDK)
import SpotifySDK
#endif

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
    public let deepLinkCoordinator = DeepLinkCoordinator()

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
        // Share links: cisum://<entity> (custom scheme) or https://cisum.studio/<entity> (Universal
        // Link). Falls through to the plugin-manifest path for `cisum://manifest?url=…` and any
        // non-deep-link URL (both parse to nil here).
        if let link = CisumLink.parse(url) {
            handleCisumDeepLink(link)
            return
        }

        Task {
            do {
                try await container.providerServices.pluginStore.install(from: url)
            } catch {
                PerfLog.debug("Failed to import provider manifest: \(error.localizedDescription)")
            }
        }
    }

    private func handleCisumDeepLink(_ link: CisumLink) {
        switch link {
        case let .song(song):
            playSharedSong(song)
        case let .playlist(playlist):
            deepLinkCoordinator.present(playlist)
        case .artist, .album:
            // Phase B: needs remote hydration.
            PerfLog.info("Received shared artist/album link (Phase B)")
        }
    }

    private func playSharedSong(_ song: SharedSong) {
        let commands = container.playbackServices.playbackCommands
        let presentation = container.appServices.playerPresentationController

        // Every provider is handled the same way now. A shared link carries a provider and an id,
        // which is exactly a PlayableRef — so there is no per-provider branch, and no rebuilding a
        // SpotifySearchTrack and a FederatedSearchItem just to construct a resolver closure.
        // A provider cisum has never seen still works, provided the user has a plugin for it.
        let ref = PlayableRef(
            songID: nil,
            sourceID: song.provider.rawValue,
            sourceTrackID: song.id,
            title: song.title,
            artist: song.artist,
            artworkURL: song.artworkURL,
            durationSeconds: song.durationSeconds
        )

        commands.load(ref, preserveQueue: false)
        presentation.expand()
    }

    /// Imports a shared playlist (from a `cisum://playlist` link) and returns its local id, or nil on
    /// failure. Embedded playlists import their carried tracklist; provider playlists re-import via the
    /// existing import services.
    public func importSharedPlaylist(_ shared: SharedPlaylist) async -> String? {
        let store = container.libraryServices.playlistLibraryStore
        do {
            switch shared {
            case let .shortened(id, _, _):
                guard let resolved = await resolveShortenedPlaylist(id: id) else { return nil }
                return await importSharedPlaylist(resolved)
            case let .embedded(name, _, _, tracks):
                return await store.importEmbeddedPlaylist(name: name, tracks: tracks)
            case let .imported(provider, sourceID, _):
                guard let link = providerShareURL(provider: provider, id: sourceID) else { return nil }
                switch provider {
                case .youtube, .youtubeMusic:
                    let service = YouTubePlaylistImportService(youtube: YouTube.shared, playlistStore: store)
                    return try await service.importPlaylist(fromLink: link)
                case .spotify:
                    return try await importSharedSpotifyPlaylist(link: link, store: store)
                default:
                    return nil
                }
            }
        } catch {
            PerfLog.warning("Shared playlist import failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func importSharedSpotifyPlaylist(link: String, store: PlaylistLibraryStore) async throws -> String {
        #if canImport(SpotifySDK)
        let coordinator = container.userServices.spotifySessionCoordinator
        await coordinator.restoreSessionIfNeeded()
        guard let sdk = coordinator.sdk ?? coordinator.session.map({ SpotifySDK(session: $0) }) else {
            throw FederatedSearchError.spotifyCredentialsMissing
        }
        let centralMediaStore = container.libraryServices.centralMediaStore
        let service = SpotifyPlaylistImportService(
            sdk: sdk,
            playlistStore: store,
            onSpotifyPlaylistImported: { playlist in
                Task { _ = await centralMediaStore.upsertSpotifyPlaylist(playlist) }
            }
        )
        return try await service.importPlaylist(fromLink: link)
        #else
        throw FederatedSearchError.providerUnavailable("Spotify is unavailable on this platform.")
        #endif
    }

    /// Resolves a shortened playlist link by fetching its payload from the shortener.
    private func resolveShortenedPlaylist(id: String) async -> SharedPlaylist? {
        guard let url = URL(string: "https://\(CisumLink.webHost)/api/share/\(id)") else { return nil }
        do {
            let payload = try await NetworkingClient.shared.get(url: url, responseType: SharedPlaylistPayload.self)
            return payload.toSharedPlaylist()
        } catch {
            PerfLog.warning("Failed to resolve shortened playlist \(id): \(error.localizedDescription)")
            return nil
        }
    }

    private func providerShareURL(provider: MediaProvider, id: String) -> String? {
        switch provider {
        case .spotify: "https://open.spotify.com/playlist/\(id)"
        case .youtube: "https://www.youtube.com/playlist?list=\(id)"
        case .youtubeMusic: "https://music.youtube.com/playlist?list=\(id)"
        default: nil
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
            #if os(iOS)
            // `PlayerThemeSettings` is an iOS-only type; the macOS player has no
            // theme selection yet, so there is nothing to inject there.
            .environment(PlayerThemeSettings.shared)
            #endif
            .environment(container.providerServices.pluginStore)
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

    /// Commands for starting playback, for callers outside the SwiftUI environment.
    public var playbackCommands: any PlaybackCommands {
        container.playbackServices.playbackCommands
    }

    public func miniPlayer(isExpanded: Binding<Bool>, namespace: Namespace.ID) -> some View {
        player.miniPlayer(isExpanded: isExpanded, namespace: namespace)
    }

    public func expandablePlayer(show: Binding<Bool>, isExpanded: Binding<Bool>, collapsedFrame: CGRect) -> some View {
        player.expandablePlayer(show: show, isExpanded: isExpanded, collapsedFrame: collapsedFrame)
    }

    /// The full player for the iOS 26 zoom cover.
    public func zoomedPlayer() -> some View {
        player.zoomedPlayer()
    }

    /// The persistent macOS transport bar.
    public func playerBar() -> some View {
        player.playerBar()
    }

    /// The rotating record behind the macOS content.
    public func vinylBackdrop() -> some View {
        player.vinylBackdrop()
    }

    #if os(iOS) || os(macOS)
    public var systemVolumeController: SystemVolumeController {
        SystemVolumeController.shared
    }
    #endif

    // MARK: - Root View

    public func applyEnvironment(to view: some View) -> some View {
        view
            .environment(\.importDownloadManager, container.libraryServices.importDownloadManager)
            .environment(\.importProgressFacade, container.libraryServices.importProgressFacade)
            .environment(container)
            .environment(container.coreServices)
            .environment(container.playbackServices)
            .environment(container.searchServices)
            .environment(container.libraryServices)
            .environment(\.playlistLibraryStore, container.libraryServices.playlistLibraryStore)
            .environment(\.savedLibrary, container.libraryServices.savedLibrary)
            .environment(\.centralMediaStore, container.libraryServices.centralMediaStore)
            .environment(container.userServices)
            .environment(container.providerServices)
            .environment(container.appServices)
            .environment(container.appServices.playerPresentationController)
            .environment(container.appServices.searchOverlayController)
            // The four state objects go in individually rather than as one player, so a view
            // takes only what it reads. That is the entire payoff of the frequency-based split in
            // PlayerState.swift — injecting a single object would put the 30 Hz fan-out straight
            // back.
            .environment(container.playbackServices.nowPlayingState)
            .environment(container.playbackServices.transportState)
            .environment(container.playbackServices.progressState)
            .environment(container.playbackServices.lyricsPresentation)
            .environment(\.playbackCommands, container.playbackServices.playbackCommands)
            .environment(\.preferredSourceIDs, container.providerServices.preferredSourceIDs)
            .environment(\.searchViewModel, container.searchServices.searchViewModel)
            .environment(container.userServices.authService)
            .environment(container.userServices.spotifySessionCoordinator)
            .environment(container.userServices.supabaseService)
            .environment(container.userServices.analyticsService)
            .environment(container.playbackServices.lastFMSettings)
            .environment(\.lastFMScrobbler, container.playbackServices.lastFMScrobbler)
            .environment(container.playbackServices.streamingProviderSettings)
            .environment(container.providerServices.pluginStore)
            #if os(iOS)
            .environment(PlayerThemeSettings.shared)
            #endif
            .modelContainer(modelContainer)
    }

    @ViewBuilder
    public var rootView: some View {
        let authService = container.userServices.authService
        // Show home immediately (it has its own loading placeholders). Only fall back to login
        // once the initial session check confirms there's genuinely no session — this avoids the
        // login-screen flash for signed-in users without an intermediate splash.
        if authService.isAuthenticated || authService.isGuestMode || !authService.hasResolvedInitialSession {
            Aesthetics.RootView(playerOverlayState: .init()) {
                self.applyEnvironment(to: RootView(module: self))
            } overlayWrapper: { overlay in
                AnyView(self.applyEnvironment(to: overlay))
            }
            .overlay(alignment: .bottom) {
                ImportProgressToastView(
                    facade: container.libraryServices.importProgressFacade,
                    manager: container.libraryServices.importDownloadManager
                )
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
            dependencies: PlayerDependencies(viewModel: container.playbackServices.player)
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
