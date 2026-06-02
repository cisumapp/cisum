import Aesthetics
import Combine
import Player
import Search
import SwiftUI
import Utilities
#if os(iOS)
import UIKit
#endif
#if canImport(SpotifySDK)
import SpotifySDK
#endif

public struct RootView: View {
    public let cisum: cisumModule

    @Environment(\.modelContext) private var modelContext
    let navigationState: NavigationState

    @Environment(ServicesContainer.self) private var container

    #if os(iOS)
    @State private var isScrollingDown = false
    @State private var storedOffset: CGFloat = 0
    @State var scrollPhase: ScrollPhases = .idle
    @State var tabBarVisibility: Visibility = .visible
    @Namespace private var playerAnimationNamespace
    @State private var showProfile = false
    @State private var showSettings = false
    @State private var appOrientation = AppOrientation(UIDevice.current.orientation)
    #else
    private var searchOverlay: SearchOverlayController {
        container.app.searchOverlayController
    }

    @Environment(\.isDynamicPlayerExpanded) private var isDynamicPlayerExpanded
    #endif

    public init(module: cisumModule) {
        self.cisum = module
        self.navigationState = module.navigationState
    }

    public var body: some View {
        #if os(iOS)
        @Bindable var presentation = container.app.playerPresentationController
        @Bindable var nav = navigationState

        iOSTabView(
            selection: selectedTabBinding,
            expandMiniPlayer: $presentation.isExpanded,
            playerAnimationNamespace: playerAnimationNamespace,
            searchText: cisum.searchText,
            playerContent: AnyView(cisum.applyEnvironment(to: cisum.expandablePlayer(
                show: .constant(true),
                isExpanded: $presentation.isExpanded,
                collapsedFrame: .zero
            ))),
            accentColor: cisum.playerAccentColor
        ) {
            Tab("Home", systemImage: "house.fill", value: TabItem.home) {
                cisum.applyEnvironment(to: tabRoot(for: .home) {
                    cisum.homeView
                })
            }

            Tab("Discover", systemImage: "globe", value: TabItem.discover) {
                cisum.applyEnvironment(to: tabRoot(for: .discover) {
                    cisum.discoverView
                })
            }

            Tab("Library", systemImage: "music.note.list", value: TabItem.library) {
                cisum.applyEnvironment(to: tabRoot(for: .library) {
                    cisum.libraryView
                })
            }

            Tab("Search", systemImage: "magnifyingglass", value: TabItem.search, role: .search) {
                cisum.applyEnvironment(to: tabRoot(for: .search) {
                    cisum.searchView
                })
            }
        } onSearchSubmit: {
            cisum.performSearch()
        }
        .tabbarBottomViewAccessory {
            cisum.applyEnvironment(to: cisum.miniPlayer(
                isExpanded: $presentation.isExpanded,
                namespace: playerAnimationNamespace
            ))
        }
        .tabbarVisibility(tabBarVisibility)
        .animation(.smooth(duration: 0.3), value: tabBarVisibility)
        .systemVolumeController(cisum.systemVolumeController, showsSystemVolumeHUD: false)
        .appOrientation(appOrientation)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateAppOrientation()
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateAppOrientation()
        }
        .onChange(of: navigationState.selectedTab) { _, _ in
            if tabBarVisibility != .visible {
                tabBarVisibility = .visible
            }
        }
        .usingRouter(cisum.router)
        .background {
            Color.cisumBg
                .ignoresSafeArea()
            spotifyBackgroundRefresh
        }
        #else
        tabSurface
            .onPreferenceChange(SearchOverlayContextPreferenceKey.self) { newContext in
                searchOverlay.updateContext(newContext)
            }
            .overlay(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .allowWindowDrag()

                SearchOverlayBar()
                    .padding(8)
            }
            .overlay(alignment: .topLeading) {
                ProfileButton(onAction: handleProfileAction)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                DynamicPlayerIsland()
                    .padding(8)
            }
            .background {
                backgroundFill
                spotifyBackgroundRefresh
            }
            .environment(\.isDynamicPlayerExpanded, isDynamicPlayerExpanded)
            .ignoresSafeArea()
            .usingRouter(cisum.router)
        #endif
    }

    @ViewBuilder
    private var spotifyBackgroundRefresh: some View {
        #if canImport(SpotifySDK)
        if let session = container.user.spotifySessionCoordinator.session {
            SpotifySilentRefreshView(session: session)
        }
        if let fallbackSession = container.user.spotifySessionCoordinator.anonymousFallbackSession {
            SpotifySilentRefreshView(session: fallbackSession)
        }
        #endif
    }

    private func handleProfileAction(_ action: ProfileMenuAction) {
        switch action {
        case .profile:
            cisum.router.navigate(to: .profile)
        case .settings:
            cisum.router.navigate(to: .settings)
        case .plugins:
            cisum.router.navigate(to: .plugins)
        }
    }

    #if os(iOS)
    private var selectedTabBinding: Binding<TabItem> {
        Binding(
            get: { cisum.navigationState.selectedTab },
            set: { cisum.navigationState.selectedTab = $0 }
        )
    }

    private func expandPlayer() {
        container.app.playerPresentationController.expand()
    }

    private func collapsePlayer() {
        container.app.playerPresentationController.collapse()
    }

    private func togglePlayerExpansion() {
        container.app.playerPresentationController.toggle()
    }

    private func updateAppOrientation() {
        let nextOrientation = AppOrientation(UIDevice.current.orientation)
        if nextOrientation != .unknown, nextOrientation != .flat {
            appOrientation = nextOrientation
        }
    }

    private func tabRoot(for tab: TabItem, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack(path: navigationState.binding(for: tab)) {
            content()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .profile:
                        cisum.profileView
                    case .settings:
                        cisum.settingsView
                    case .plugins:
                        cisum.pluginsView
                    case let .playlist(id):
                        cisum.playlistDetailView(for: id)
                    case let .artist(id):
                        cisum.artistDetailView(for: id)
                    case let .album(id):
                        cisum.albumDetailView(for: id)
                    case .login:
                        cisum.loginView
                    case .spotifyLogin:
                        #if canImport(SpotifySDK)
                        cisum.spotifyLoginView
                        #else
                        EmptyView()
                        #endif
                    case .youtubeLogin:
                        cisum.youtubeLoginView
                    case .home:
                        cisum.homeView
                    case .search:
                        cisum.searchView
                    case .library:
                        cisum.libraryView
                    case .recents:
                        cisum.libraryView
                    }
                }
                .onScrollOffsetChange { oldValue, newValue in
                    let scrollingDown = oldValue < newValue

                    if isScrollingDown != scrollingDown {
                        let adjustedOffset = newValue - (tabBarVisibility == .hidden ? 20 : 0)
                        if storedOffset != adjustedOffset {
                            storedOffset = adjustedOffset
                        }
                        isScrollingDown = scrollingDown
                    }

                    let diff = newValue - storedOffset
                    if scrollPhase == .interacting {
                        if diff > AppConstants.hideThresholds {
                            if tabBarVisibility != .hidden {
                                tabBarVisibility = .hidden
                            }
                        } else if diff < AppConstants.showThresholds {
                            if tabBarVisibility != .visible {
                                tabBarVisibility = .visible
                            }
                        }
                    }
                }
                .onScrollPhaseUpdate { _, newPhase in
                    if scrollPhase != newPhase {
                        scrollPhase = newPhase
                    }
                }
        }
    }
    #else
    @ViewBuilder
    private var backgroundFill: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.92))
        }
    }

    private var tabSurface: some View {
        tabRoot(for: navigationState.selectedTab) {
            selectedTabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentMargins(.top, 80)
        .contentMargins(.trailing, isDynamicPlayerExpanded.wrappedValue ? 430 : 0)
        .animation(.playerExpandAnimation, value: isDynamicPlayerExpanded.wrappedValue)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch navigationState.selectedTab {
        case .home:
            cisum.homeView
        case .discover:
            cisum.discoverView
        case .library:
            cisum.libraryView
        case .search:
            cisum.searchView
        }
    }

    private func tabRoot(for tab: TabItem, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack(path: navigationState.binding(for: tab)) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .profile:
                        cisum.profileView
                    case .settings:
                        cisum.settingsView
                    case .plugins:
                        cisum.pluginsView
                    case let .playlist(id):
                        cisum.playlistDetailView(for: id)
                    case let .artist(id):
                        cisum.artistDetailView(for: id)
                    case let .album(id):
                        cisum.albumDetailView(for: id)
                    case .login:
                        cisum.loginView
                    case .spotifyLogin:
                        #if canImport(SpotifySDK)
                        cisum.spotifyLoginView
                        #else
                        EmptyView()
                        #endif
                    case .youtubeLogin:
                        cisum.youtubeLoginView
                    case .home:
                        cisum.homeView
                    case .search:
                        cisum.searchView
                    case .library:
                        cisum.libraryView
                    case .recents:
                        cisum.libraryView
                    }
                }
        }
    }
    #endif
}
