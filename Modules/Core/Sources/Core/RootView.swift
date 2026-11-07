import Aesthetics
import Combine
import Library
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
    @Namespace private var tabPillNamespace

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
                    zoomedPlayerContent: cisum.applyEnvironment(to: cisum.zoomedPlayer())
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
                    zoomedPlayerContent: cisum.applyEnvironment(to: cisum.zoomedPlayer())
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
        MacSidebar(navigationState: navigationState)
        // The list draws its own sidebar material, which would sit *on top of* the glass
        // surface behind it and make the translucency invisible. Hiding it lets the glass
        // through while keeping the native rows, metrics and selection — the surface below
        // is what you actually see.
        .scrollContentBackground(.hidden)
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
        // Applied last so it moves the surface and everything inside it away from the
        // window edge together, leaving the canvas showing around it.
        //
        // Leading, top and bottom are inset; the trailing side is not. The split
        // view's divider is the column's own trailing edge, so insetting that side
        // too would strand the surface 10pt short of it — a strip of empty canvas
        // that still drags the divider, so the surface's edge and the resize
        // boundary stop reading as the same line. The insets come from
        // `MacSplitView`, which sizes the column they have to fit inside.
        .padding(EdgeInsets(
            top: MacSplitView.sidebarMargin,
            leading: MacSplitView.sidebarMargin,
            bottom: MacSplitView.sidebarMargin,
            trailing: 0
        ))
        // The canvas behind the margin. Without it the bare window background shows through the
        // gutter, and on a light appearance that is a pale frame around a dark sidebar.
        .background(Color.cisumBg)
    }

    /// The navigation column's surface.
    ///
    /// A *floating* surface, not a structural region: it is inset from the window edge on
    /// every side, rounded on all four corners, and translucent enough to pick up the canvas
    /// behind it. That is what separates it from a docked sidebar, which is flush to the
    /// frame, square on its divider edge, and opaque.
    ///
    /// The dark scrim under the material is load-bearing, not decoration. `glassEffect(.regular)`
    /// and `.ultraThinMaterial` both resolve to a mid-grey in a dark window — measured around
    /// 20% luminance — which reads as a light grey panel rather than a dark translucent one,
    /// and leaves the sidebar reading lighter than the content it is supposed to sit behind.
    /// Laying the canvas colour over the material brings it down to roughly 10%: dark, still
    /// translucent, and clearly separated from the canvas by the edge highlight rather than by
    /// being brighter than it.
    @ViewBuilder
    private var sidebarMaterial: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Self.sidebarCornerRadius,
            bottomLeadingRadius: Self.sidebarCornerRadius,
            bottomTrailingRadius: Self.sidebarCornerRadius,
            topTrailingRadius: Self.sidebarCornerRadius,
            style: .continuous
        )
        Group {
            if #available(macOS 26.0, *) {
                shape.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            shape.fill(Color.cisumBg.opacity(Self.sidebarScrimOpacity))
        }
        // `glassEffect` draws its own highlight, but the scrim above sits on top of it, so the
        // leading edge would otherwise lose the one cue that separates the panel from the
        // canvas it floats over.
        .overlay {
            shape.strokeBorder(Color.cisumChromeSubtle, lineWidth: 1)
        }
    }

    /// How far the canvas colour is laid over the sidebar's material.
    ///
    /// Tuned against measured luminance rather than by eye: the material alone sits near 20%
    /// and this brings the surface to roughly 10%, which is where the reference's sidebar
    /// sits relative to its canvas.
    private static let sidebarScrimOpacity: Double = 0.55

    /// Corner radius of the floating surfaces. Wide enough to read as a detached panel rather
    /// than a slightly-softened rectangle, but not so wide that it looks like a sheet.
    private static let sidebarCornerRadius: CGFloat = 14

    /// Trailing edge of the traffic lights, measured from the sidebar's leading edge: the
    /// 14pt inset plus three 12pt buttons and two 8pt gaps. `WindowDragRegion` starts here so
    /// the two never overlap.
    private static let windowControlsWidth: CGFloat = 14 + 3 * 12 + 2 * 8
    #endif

    #if !os(iOS)
    /// The shell every macOS tab sits in: the tab's content filling the window over the record,
    /// with the transport and the navigation row floating above it.
    ///
    /// Living here rather than in each tab is the point — the chrome is not content, so Home,
    /// Discover, Library and Search all get the same structure without any of them knowing
    /// about it. Content scrolls up under the chrome, softened by a fade, rather than stopping
    /// at a band below it.
    private var detailColumn: some View {
        ZStack(alignment: .top) {
            // The record, tinted by the current track's artwork. Sized from the geometry
            // because both layers are scaled-to-fill images with no size of their own.
            GeometryReader { proxy in
                ZStack {
                    backgroundFill
                    cisum.artworkBackdrop()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.55)
                    cisum.vinylBackdrop()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
            }
            .ignoresSafeArea()

            tabSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onPreferenceChange(SearchOverlayContextPreferenceKey.self) { newContext in
                    searchOverlay.updateContext(newContext)
                }
                .environment(\.isDynamicPlayerExpanded, isDynamicPlayerExpanded)
                .usingRouter(cisum.router)
                // Content starts below the chrome and scrolls up under it. A safe-area inset
                // rather than content margins: margins reach every nested scroll view, which
                // would push each horizontal shelf down by the same amount.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        Color.clear.frame(height: Self.chromeHeight)
                        // The search field sits on the Search surface only.
                        if navigationState.selectedTab == .search {
                            SearchOverlayBar()
                        }
                    }
                }

            // Keeps the chrome legible over whatever scrolls beneath it.
            LinearGradient(
                stops: [
                    .init(color: Color.cisumBg.opacity(0.85), location: 0),
                    .init(color: Color.cisumBg.opacity(0.6), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.chromeHeight + 40)
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                cisum.playerBar()
                navigationRow
            }
            .padding(.top, 12)
            .padding(.horizontal, 36)

            spotifyBackgroundRefresh
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Height of the floating chrome — the transport, the navigation row and the gaps around
    /// them — which content starts below.
    private static let chromeHeight: CGFloat = 128

    /// Back and forward at the leading edge, the tabs in the middle.
    private var navigationRow: some View {
        ZStack {
            tabPill
            HStack {
                historyPill
                Spacer()
            }
        }
    }

    /// Back, and a forward that stays dimmed: `NavigationPath` keeps no forward history, so
    /// the control is there for the layout's balance and shows it has nowhere to go.
    private var historyPill: some View {
        HStack(spacing: 6) {
            Button {
                // `NavigationPath` is a `RangeReplaceableCollection` over its elements, so going
                // back is dropping the last one, written back through the same dictionary the
                // tab's `NavigationStack` is bound to.
                var path = navigationState.tabPaths[navigationState.selectedTab] ?? NavigationPath()
                guard !path.isEmpty else { return }
                path.removeLast()
                navigationState.tabPaths[navigationState.selectedTab] = path
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 20, height: 32)
                    .contentShape(.rect)
            }
            .disabled(!navigationPillShowsBack)
            .help("Back")

            Rectangle()
                .fill(Color.cisumChromeSubtle)
                .frame(width: 1, height: 15)

            Image(systemName: "chevron.right")
                .frame(width: 20, height: 32)
                .foregroundStyle(.quaternary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .background { navigationPillSurface }
    }

    /// One button per tab, with a highlight that slides to the selected one.
    private var tabPill: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases, id: \.self) { tab in
                let isActive = navigationState.selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                        selectTab(tab)
                    }
                } label: {
                    Image(systemName: Self.pillIcon(for: tab))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? Color.cisumPrimaryText : Color.cisumSecondaryText)
                        .frame(width: 60, height: 37)
                        .background {
                            if isActive {
                                Capsule(style: .continuous)
                                    .fill(Color.cisumChromeSubtle)
                                    .matchedGeometryEffect(id: "tab-highlight", in: tabPillNamespace)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(4)
        .background { navigationPillSurface }
    }

    /// The design's glyphs for the pill, which are outline symbols unlike the iOS tab bar's.
    private static func pillIcon(for tab: TabItem) -> String {
        switch tab {
        case .home: "house"
        case .discover: "flame"
        case .library: "music.note.square.stack"
        case .search: "magnifyingglass"
        }
    }

    /// Whether the current tab has somewhere to go back to.
    private var navigationPillShowsBack: Bool {
        (navigationState.tabPaths[navigationState.selectedTab]?.count ?? 0) > 0
    }

    private var navigationPillSurface: some View {
        let shape = Capsule(style: .continuous)
        return Group {
            if #available(macOS 26.0, *) {
                shape.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        // Same scrim as the sidebar and the transport, so all three floating surfaces sit at
        // one key instead of the pill reading lighter than the bar directly above it.
        .overlay {
            shape.fill(Color.cisumBg.opacity(0.4))
        }
        .overlay {
            shape.strokeBorder(Color.cisumChromeSubtle, lineWidth: 1)
        }
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
            set: { selectTab($0) }
        )
    }

    /// A tab tapped in the tab bar or the macOS tab pill: the tab that's already showing
    /// pops back to its root, any other tab is switched to with its own stack intact.
    private func selectTab(_ tab: TabItem) {
        if tab == cisum.navigationState.selectedTab {
            cisum.router.popToRoot()
        } else {
            cisum.navigationState.selectedTab = tab
        }
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
                    case .librarySongs:
                        cisum.applyEnvironment(to: LibraryPage(.songs))
                    case .libraryAlbums:
                        cisum.applyEnvironment(to: LibraryPage(.albums))
                    case .libraryArtists:
                        cisum.applyEnvironment(to: LibraryPage(.artists))
                    case .libraryPlaylists:
                        cisum.applyEnvironment(to: LibraryPage(.playlists))
                    case let .libraryAlbum(id):
                        cisum.applyEnvironment(to: LibraryPage(.album(id)))
                    case let .libraryArtist(id):
                        cisum.applyEnvironment(to: LibraryPage(.artist(id)))
                    case .equalizer:
                        cisum.applyEnvironment(to: EqualizerView())
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
                // Cards open over the tab's content but under the tab bar and its accessory.
                .universalOverlayHost(id: "\(tab)")
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
        // Clears the floating search field — but only on Search, where that field is drawn.
        //
        // The reservation is tied to the same condition as the overlay below because an
        // unconditional one would leave a 56pt empty strip above the content on Home,
        // Discover, Library and any pushed detail: the space would still be held open for a
        // field that is no longer there. Search lays its own results out independently, so
        // removing the reservation where the field is absent changes nothing there.
        // The transport lives in the band above rather than floating over this, so there is
        // nothing to clear at the bottom.
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
                    case .librarySongs:
                        cisum.applyEnvironment(to: LibraryPage(.songs))
                    case .libraryAlbums:
                        cisum.applyEnvironment(to: LibraryPage(.albums))
                    case .libraryArtists:
                        cisum.applyEnvironment(to: LibraryPage(.artists))
                    case .libraryPlaylists:
                        cisum.applyEnvironment(to: LibraryPage(.playlists))
                    case let .libraryAlbum(id):
                        cisum.applyEnvironment(to: LibraryPage(.album(id)))
                    case let .libraryArtist(id):
                        cisum.applyEnvironment(to: LibraryPage(.artist(id)))
                    case .equalizer:
                        cisum.applyEnvironment(to: EqualizerView())
                    }
                }
        }
    }
    #endif
}
