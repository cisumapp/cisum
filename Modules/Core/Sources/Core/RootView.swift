import Aesthetics
import Combine
import Models
import Networking
import Player
import Search
import SwiftData
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

    /// Shared by both platform branches. The macOS island has no namespace-driven
    /// transitions, so it ignores this — but routing it through `PlayerModule.miniPlayer`
    /// keeps a single entry point that is guaranteed to inject the player environment.
    @Namespace private var playerAnimationNamespace

    #if os(iOS)
    @State private var isScrollingDown = false
    @State private var storedOffset: CGFloat = 0
    @State var scrollPhase: ScrollPhases = .idle
    @State var tabBarVisibility: Visibility = .visible
    @State private var showProfile = false
    @State private var showSettings = false
    @State private var appOrientation = AppOrientation(UIDevice.current.orientation)
    @State private var updateChecker = AppUpdateChecker()
    /// iOS 26 zoom cover presentation — local @State so tapping the accessory
    /// does NOT trigger RootView.body re-evaluation (which would destroy the
    /// matchedTransitionSource identity).
    @State private var isPlayerCoverPresented = false
    @Environment(\.openURL) private var openURL
    #else
    private var searchOverlay: SearchOverlayController {
        container.appServices.searchOverlayController
    }

    @Environment(\.isDynamicPlayerExpanded) private var isDynamicPlayerExpanded
    #endif
    public init(module: cisumModule) {
        self.cisum = module
        self.navigationState = module.navigationState
    }

    public var body: some View {
        #if os(iOS)
        @Bindable var presentation = container.appServices.playerPresentationController
        @Bindable var nav = navigationState
        @Bindable var deepLink = cisum.deepLinkCoordinator

        // iOS 26: replicate the reference project pattern exactly — source + cover in
        // the NON-GENERIC RootView body, with @Namespace owned locally and modifiers
        // applied directly (no @ViewBuilder wrappers).  This is required because
        // SwiftUI's zoom transition cannot track source identity inside generic views.
        Group {
            if #available(iOS 26.0, *) {
                iOSTabView(
                    selection: selectedTabBinding,
                    expandMiniPlayer: $presentation.isExpanded,
                    playerAnimationNamespace: playerAnimationNamespace,
                    searchText: cisum.searchText,
                    playerContent: cisum.applyEnvironment(to: cisum.expandablePlayer(
                        show: .constant(true),
                        isExpanded: $presentation.isExpanded,
                        collapsedFrame: .zero
                    )),
                    miniPlayerContent: cisum.applyEnvironment(to: cisum.miniPlayer(
                        isExpanded: $presentation.isExpanded,
                        namespace: playerAnimationNamespace
                    )),
                    zoomedPlayerContent: cisum.applyEnvironment(to: cisum.zoomedPlayer()),
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

                    Tab("Search", systemImage: "magnifyinglass", value: TabItem.search, role: .search) {
                        cisum.applyEnvironment(to: tabRoot(for: .search) {
                            cisum.searchView
                        })
                    }
                } onSearchSubmit: {
                    cisum.performSearch()
                }
                .tabViewBottomAccessory {
                    cisum.applyEnvironment(to: cisum.miniPlayer(
                        isExpanded: $presentation.isExpanded,
                        namespace: playerAnimationNamespace
                    ))
                    .matchedTransitionSource(id: PlayerZoomID.miniPlayer, in: playerAnimationNamespace)
                    .contentShape(.rect)
                    .highPriorityGesture(TapGesture().onEnded {
                        isPlayerCoverPresented.toggle()
                    })
                }
            } else {
                iOSTabView(
                    selection: selectedTabBinding,
                    expandMiniPlayer: $presentation.isExpanded,
                    playerAnimationNamespace: playerAnimationNamespace,
                    searchText: cisum.searchText,
                    playerContent: cisum.applyEnvironment(to: cisum.expandablePlayer(
                        show: .constant(true),
                        isExpanded: $presentation.isExpanded,
                        collapsedFrame: .zero
                    )),
                    miniPlayerContent: cisum.applyEnvironment(to: cisum.miniPlayer(
                        isExpanded: $presentation.isExpanded,
                        namespace: playerAnimationNamespace
                    )),
                    zoomedPlayerContent: cisum.applyEnvironment(to: cisum.zoomedPlayer()),
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

                    Tab("Search", systemImage: "magnifyinglass", value: TabItem.search, role: .search) {
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
            }
        }
        .fullScreenCover(isPresented: $isPlayerCoverPresented) {
            Group {
                if #available(iOS 18.0, *) {
                    cisum.applyEnvironment(to: cisum.zoomedPlayer())
                        .navigationTransition(.zoom(sourceID: PlayerZoomID.miniPlayer, in: playerAnimationNamespace))
                } else {
                    cisum.applyEnvironment(to: cisum.zoomedPlayer())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .environment(\.profileImageURL, profileImageURL)
        .background {
            spotifyBackgroundRefresh
        }
        .alert(
            deepLink.pendingPlaylist.map { "Add “\($0.playlist.displayName)” to your library?" } ?? "",
            isPresented: Binding(
                get: { deepLink.pendingPlaylist != nil },
                set: {
                    if !$0 {
                        deepLink.pendingPlaylist = nil
                    }
                }
            ),
            presenting: deepLink.pendingPlaylist
        ) { pending in
            Button("nvm", role: .cancel) {}
            Button("okayy") {
                Task {
                    if await cisum.importSharedPlaylist(pending.playlist) != nil {
                        // Land in the Library (under "Shared"), not a pushed detail.
                        cisum.router.navigate(to: .library)
                    }
                }
            }
        } message: { pending in
            Text(sharedPlaylistMessage(pending.playlist))
        }
        .task {
            await updateChecker.check()
        }
        .alert("Update Available", isPresented: $updateChecker.updateAvailable) {
            Button("Download") {
                if let url = updateChecker.downloadURL {
                    openURL(url)
                }
            }
            // ponytail: forced = drop "Later" (only escape is Download → TestFlight); re-prompts next launch.
            if !updateChecker.forced {
                Button("Later", role: .cancel) {}
            }
        } message: {
            Text(updateChecker.message)
        }
        #else
        // A native sidebar next to the content, with no strip across the top of the window.
        //
        // `MacSplitView` is `NSSplitViewController` hosted directly rather than SwiftUI's
        // `NavigationSplitView`, so the columns start at the window's true top edge. The list
        // is still native — `.listStyle(.sidebar)` draws the rows, selection and material —
        // and the divider is AppKit's, so the sidebar resizes the way a Mac sidebar does.
        //
        // The window itself stays titled. That is what keeps keyboard focus, the system
        // corner radius and the native resize edges, none of which a borderless window has.
        MacSplitView(
            sidebar: sidebarColumn,
            detail: detailColumn,
            detailKey: navigationState.selectedTab.index
        )
        // The window is created with `fullSizeContentView`, so its content view spans the
        // full window — but AppKit still lays views out against the window's *content layout
        // rect*, which excludes the title bar. That inset is what draws a strip above the
        // sidebar and the record band, and it is applied by the layout guide above this view,
        // so no `.toolbar` modifier can reach it.
        //
        // `.all` is required: `.container` resolves to the nearest container (the hosting
        // view) rather than the window, which is why earlier attempts with `.container` had
        // no effect. This matches how the Ora browser does it.
        .ignoresSafeArea(.all)
        #endif
    }

    #if !os(iOS)
    /// The navigation column: a native sidebar list with the window's traffic lights
    /// drawn inside it.
    private var sidebarColumn: some View {
        List(selection: selectedTabBinding) {
            ForEach(TabItem.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        // Reserves the strip the traffic lights occupy. The controls are an overlay, and
        // without this they would land on top of the first row. A `safeAreaInset` is used
        // rather than padding so the row's own metrics and selection stay intact.
        //
        // This has to come *before* the two overlays below. Applied after them it shrinks the
        // bounds they align to, which drops the controls onto the "Home" row instead of
        // parking them 14pt from the top of the window.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 34)
        }
        // The window can only be dragged from this strip.
        //
        // `isMovableByWindowBackground` would make all of it work, but that also makes every
        // empty pixel draggable — including the sliver beside the resize handle, so grabbing
        // it to resize the column drags the window instead. `mouseDownCanMoveWindow` limits
        // dragging to this header, which is where a title bar's drag area normally lives.
        //
        // Added before the controls, and inset past them, because this view swallows the
        // mouse-down to start a window drag. Laid over the traffic lights it made all three
        // of them dead: the drag began instead of the tap, so close, minimise and zoom never
        // ran.
        .overlay(alignment: .top) {
            WindowDragRegion()
                .padding(.leading, Self.windowControlsWidth)
                .frame(height: 34)
        }
        .overlay(alignment: .topLeading) {
            WindowControls()
                .padding(.leading, 14)
                .padding(.top, 14)
        }
        .background { sidebarMaterial }
    }

    /// The navigation column's surface.
    ///
    /// A sidebar is a *structural* region, so its material stays the heavy, dark one rather
    /// than a prominent tint — weight encodes hierarchy here. On macOS 26 the system draws
    /// this itself for a `.sidebar` list, so the native material is left showing; the glass
    /// below is only reached once the list's own background is hidden, which is what lets the
    /// content behind the column show through instead.
    ///
    /// Only the two leading corners are rounded. The trailing edge meets the split view's
    /// divider and must stay square, and the window's own corners clip the top and bottom
    /// against the frame.
    @ViewBuilder
    private var sidebarMaterial: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Self.windowCornerRadius,
            bottomLeadingRadius: Self.windowCornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        if #available(macOS 26.0, *) {
            shape.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    /// The window's corner radius. Matches what AppKit draws for a standard titled window, so
    /// the sidebar's leading edge meets the frame without a visible step.
    private static let windowCornerRadius: CGFloat = 10

    /// Trailing edge of the traffic lights, measured from the sidebar's leading edge: the
    /// 14pt inset plus three 12pt buttons and two 8pt gaps. `WindowDragRegion` starts here so
    /// the two never overlap.
    private static let windowControlsWidth: CGFloat = 14 + 3 * 12 + 2 * 8
    #endif

    #if !os(iOS)
    /// The shell every macOS tab sits in: a record band with the transport floating over
    /// it, and the tab's content permanently underneath.
    ///
    /// Living here rather than in each tab is the point — the band and the bar are chrome,
    /// not content, so Home, Discover, Library and Search all get the same structure without
    /// any of them knowing about it.
    private var detailColumn: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // ── The record band ──────────────────────────────────────────
                // The disc is only ever visible in this strip. The transport floats inside
                // it, near its bottom edge; everything below is opaque content, so the
                // record reads as peeking out from behind the interface rather than as
                // wallpaper behind it.
                ZStack {
                    cisum.vinylBackdrop()

                    VStack {
                        Spacer(minLength: 0)
                        cisum.playerBar()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                }
                .frame(height: Self.vinylBandHeight(for: proxy.size.height, width: proxy.size.width))
                .clipped()

                // ── Opaque content ───────────────────────────────────────────
                // The fill is applied at the shell rather than in each tab, so no view can
                // end up transparent over the window.
                tabSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { backgroundFill }
                    .onPreferenceChange(SearchOverlayContextPreferenceKey.self) { newContext in
                        searchOverlay.updateContext(newContext)
                    }
                    .environment(\.isDynamicPlayerExpanded, isDynamicPlayerExpanded)
                    .usingRouter(cisum.router)
                    // Over the content, not the record: the band holds the transport and
                    // nothing else, so the two never compete for the same strip.
                    .overlay(alignment: .top) {
                        SearchOverlayBar()
                            .padding(.top, 8)
                    }

                spotifyBackgroundRefresh
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Height of the strip the record is visible in.
    ///
    /// Sized to clear the floating transport plus a band of record above it, and clamped
    /// against the window height so a short window doesn't hand most of the screen to the
    /// backdrop and starve the content below.
    private static func vinylBandHeight(for windowHeight: CGFloat, width windowWidth: CGFloat = 0) -> CGFloat {
        min(max(260, windowWidth * 0.1), max(120, windowHeight * 0.24))
    }
    #endif

    private func sharedPlaylistMessage(_ playlist: SharedPlaylist) -> String {
        switch playlist {
        case let .embedded(_, author, sharedBy, tracks):
            var parts = ["\(tracks.count) \(tracks.count == 1 ? "song" : "songs")"]
            if let sharedBy, !sharedBy.isEmpty {
                parts.append("shared by \(sharedBy)")
            } else if let author, !author.isEmpty {
                parts.append("by \(author)")
            }
            return parts.joined(separator: " · ")
        case .imported:
            return "Imported playlist"
        case .shortened:
            return "Shared playlist"
        }
    }

    @ViewBuilder
    private var spotifyBackgroundRefresh: some View {
        #if canImport(SpotifySDK)
        if let session = container.userServices.spotifySessionCoordinator.session {
            SpotifySilentRefreshView(session: session)
        }
        if let fallbackSession = container.userServices.spotifySessionCoordinator.anonymousFallbackSession {
            SpotifySilentRefreshView(session: fallbackSession)
        }
        #endif
    }

    private var profileImageURL: URL? {
        if let clerkUser = container.userServices.authService.user, let url = URL(string: clerkUser.imageUrl) {
            return url
        }
        if let avatar = container.userServices.spotifySessionCoordinator.accountProfile?.avatarImages.first {
            return avatar.url
        }
        return nil
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

    /// Selection for whichever primary-navigation shell is in play — the iOS tab bar or
    /// the macOS sidebar. Both drive the same `NavigationState`, so switching tabs is
    /// consistent across platforms.
    private var selectedTabBinding: Binding<TabItem> {
        Binding(
            get: { cisum.navigationState.selectedTab },
            set: { cisum.navigationState.selectedTab = $0 }
        )
    }

    #if os(iOS)
    private func expandPlayer() {
        container.appServices.playerPresentationController.expand()
    }

    private func collapsePlayer() {
        container.appServices.playerPresentationController.collapse()
    }

    private func togglePlayerExpansion() {
        container.appServices.playerPresentationController.toggle()
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
                .background(Color.cisumBg.ignoresSafeArea())
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .profile:
                        cisum.applyEnvironment(to: cisum.profileView)
                    case .settings:
                        cisum.applyEnvironment(to: cisum.settingsView)
                    case .plugins:
                        cisum.applyEnvironment(to: cisum.pluginsView)
                    case let .playlist(id):
                        cisum.applyEnvironment(to: cisum.playlistDetailView(for: id))
                    case let .artist(id):
                        cisum.applyEnvironment(to: cisum.artistDetailView(for: id))
                    case let .album(id):
                        cisum.applyEnvironment(to: cisum.albumDetailView(for: id))
                    case .login:
                        cisum.applyEnvironment(to: cisum.loginView)
                    case .spotifyLogin:
                        #if canImport(SpotifySDK)
                        cisum.applyEnvironment(to: cisum.spotifyLoginView)
                        #else
                        EmptyView()
                        #endif
                    case .youtubeLogin:
                        cisum.applyEnvironment(to: cisum.youtubeLoginView)
                    case .home:
                        cisum.applyEnvironment(to: cisum.homeView)
                    case .search:
                        cisum.applyEnvironment(to: cisum.searchView)
                    case .library:
                        cisum.applyEnvironment(to: cisum.libraryView)
                    case .recents:
                        cisum.applyEnvironment(to: cisum.libraryView)
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
    /// Opaque, so the window reads as a real surface rather than a sheet over whatever is
    /// behind it. Applied at the shell so every tab is covered without each view repeating
    /// it. Deliberately *not* glass: the reference's content area is solid, and only the
    /// sidebar and the transport float.
    private var backgroundFill: some View {
        Color.cisumBg
    }

    private var tabSurface: some View {
        tabRoot(for: navigationState.selectedTab) {
            selectedTabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Clears the floating search field. The transport lives in the band above rather
        // than floating over this, so there is nothing to clear at the bottom.
        .contentMargins(.top, 56)
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
                        cisum.applyEnvironment(to: cisum.profileView)
                    case .settings:
                        cisum.applyEnvironment(to: cisum.settingsView)
                    case .plugins:
                        cisum.applyEnvironment(to: cisum.pluginsView)
                    case let .playlist(id):
                        cisum.applyEnvironment(to: cisum.playlistDetailView(for: id))
                    case let .artist(id):
                        cisum.applyEnvironment(to: cisum.artistDetailView(for: id))
                    case let .album(id):
                        cisum.applyEnvironment(to: cisum.albumDetailView(for: id))
                    case .login:
                        cisum.applyEnvironment(to: cisum.loginView)
                    case .spotifyLogin:
                        #if canImport(SpotifySDK)
                        cisum.applyEnvironment(to: cisum.spotifyLoginView)
                        #else
                        EmptyView()
                        #endif
                    case .youtubeLogin:
                        cisum.applyEnvironment(to: cisum.youtubeLoginView)
                    case .home:
                        cisum.applyEnvironment(to: cisum.homeView)
                    case .search:
                        cisum.applyEnvironment(to: cisum.searchView)
                    case .library:
                        cisum.applyEnvironment(to: cisum.libraryView)
                    case .recents:
                        cisum.applyEnvironment(to: cisum.libraryView)
                    }
                }
        }
    }
    #endif
}
