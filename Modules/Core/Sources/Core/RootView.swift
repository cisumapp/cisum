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
        // Song taps anywhere call `presentation.expand()`; the bridge turns that into the cover. It is
        // its own view so RootView.body never reads `isExpanded` (see `isPlayerCoverPresented`).
        .background {
            ZoomCoverBridge(
                presentation: container.appServices.playerPresentationController,
                isCoverPresented: $isPlayerCoverPresented
            )
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
        // Any vertical scroll view in the window, not only each tab's first page.
        .onWindowScrollDirectionChange { scrollingDown in
            let visibility: Visibility = scrollingDown ? .hidden : .visible
            if tabBarVisibility != visibility {
                tabBarVisibility = visibility
            }
        }
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
        ZStack {
        windowBackdrop
        MacSplitView(
            sidebar: sidebarColumn,
            detail: detailColumn
                // With the sidebar folded away its traffic lights go with it, so they and the
                // way back to the sidebar move to the content's top-left corner.
                .overlay(alignment: .topLeading) {
                    CollapsedSidebarControls(navigationState: navigationState)
                },
            detailKey: navigationState.selectedTab.index,
            isSidebarCollapsed: navigationState.isSidebarCollapsed,
            onSidebarCollapsedChange: { [navigationState] collapsed in
                if navigationState.isSidebarCollapsed != collapsed {
                    navigationState.isSidebarCollapsed = collapsed
                }
            }
        )
        }
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
        // The design's header row: the account and the sidebar toggle at the trailing edge.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 13) {
                Button {
                    cisum.router.navigate(to: .profile)
                } label: {
                    Group {
                        if let profileImageURL {
                            ArtworkImage(url: profileImageURL, size: 18)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(Color.cisumSecondaryText)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .clipShape(.circle)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Profile")

                SidebarToggle(navigationState: navigationState)
            }
            .padding(.trailing, 12)
            .padding(.top, 11)
        }
        .background { sidebarMaterial }
        // Fixed width, pinned to the column's trailing edge: as the column folds the panel slides
        // out to the left whole, instead of squeezing its rows into truncated text.
        .frame(width: MacSplitView.sidebarWidth)
        .frame(maxWidth: .infinity, alignment: .trailing)
        // The overflow is clipped to the column, so the panel exits through the window's edge.
        .clipped()
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
        // No fill behind the margin: the window-level backdrop is the canvas there, so the record
        // shows around the floating sidebar as it does in the design.
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
        // Dark material, not Liquid Glass: `glassEffect` (plain or tinted) resolved to a light grey
        // here, which washed out the white text on it.
        shape.fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        .overlay {
            shape.fill(Color.black.opacity(Self.sidebarScrimOpacity))
        }
        .overlay {
            shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom))
        }
        // `glassEffect` draws its own highlight, but the scrim above sits on top of it, so the
        // leading edge would otherwise lose the one cue that separates the panel from the
        // canvas it floats over.
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    /// How far the canvas colour is laid over the sidebar's material.
    ///
    /// Tuned against measured luminance rather than by eye: the material alone sits near 20%
    /// and this brings the surface to roughly 10%, which is where the reference's sidebar
    /// sits relative to its canvas.
    // 0.75, not 0.55: over a light desktop the glass let enough through that the panel read as
    // grey against the design's near-black sidebar.
    private static let sidebarScrimOpacity: Double = 0.15

    /// Corner radius of the floating surfaces. Wide enough to read as a detached panel rather
    /// than a slightly-softened rectangle, but not so wide that it looks like a sheet.
    private static let sidebarCornerRadius: CGFloat = 26 - MacSplitView.sidebarMargin

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
            // No backdrop of its own: the record is a window-level layer under both columns
            // (`windowBackdrop`), as in the design's layer order.
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
                        Color.clear.frame(height: Self.chromeHeight + Self.discReveal)
                        // The search field sits on the Search surface only.
                        if navigationState.selectedTab == .search {
                            SearchOverlayBar()
                        }
                    }
                }
                // Content fades out as it scrolls up toward the chrome (after the inset, so this
                // measures from the window top), so it never covers the
                // record behind the bar and pills.
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: Self.contentFadeTop)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.chromeHeight + Self.discReveal - Self.contentFadeTop)
                        Color.black
                    }
                }


            VStack(spacing: 14) {
                cisum.playerBar()
                navigationRow
            }
            // The design's bar sits low enough that the record's rim shows above it.
            .padding(.top, Self.chromeTop)
            .padding(.horizontal, 36)

            spotifyBackgroundRefresh
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole column, chrome included: it is its own hosting controller and inherits none of
        // RootView's environment, so the player bar's "…" had the no-op router and Equalizer did
        // nothing.
        .usingRouter(cisum.router)
    }

    /// The bottom layer of the window, under both columns (the design's layer order: the record
    /// first, then the content, the chrome and the sidebar's glass over it). The canvas colour,
    /// the playing track's artwork washed out, then the record — centred on the content area so
    /// it slides over when the sidebar folds away.
    private var windowBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundFill
                cisum.artworkBackdrop()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(0.55)
                // Only the disc follows the sidebar, centring on the content; the wash and frost
                // around it are window-wide and stay put.
                cisum.vinylBackdrop(
                    leadingInset: navigationState.isSidebarCollapsed ? 0 : MacSplitView.sidebarColumnWidth
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                contentCover
            }
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// Frosts the record under the content, so only its top arc shows clear, behind the player
    /// bar, and every tab reads on a dark, still surface instead of moving grooves.
    private var contentCover: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            Color.cisumBg.opacity(0.25)
        }
        // Never fully opaque, so the record still reads faintly under the content.
        .opacity(0.75)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.discBandFade)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, Self.discBandHeight)
            .background(alignment: .bottom) {
                Color.black.padding(.top, Self.discBandHeight + Self.discBandFade)
            }
        }
        // One band across the whole window: the sidebar floats on the same canvas as the content,
        // so nothing here depends on whether it is shown.
        .allowsHitTesting(false)
    }

    /// The clear strip of record behind the player bar, then the fade into the frost.
    /// The same band the scrolled content fades over, so the frost and the content start together.
    private static let discBandHeight: CGFloat = contentFadeTop
    private static let discBandFade: CGFloat = chromeHeight + discReveal - contentFadeTop

    /// Height of the floating chrome — the transport, the navigation row and the gaps around
    /// them — which content starts below.
    private static let chromeHeight: CGFloat = chromeTop + 116

    /// Where the player bar starts (the design's 118pt in a 784pt window).
    private static let chromeTop: CGFloat = 116

    /// Above this, scrolled content is fully hidden (just under the tab pill).
    private static let contentFadeTop: CGFloat = chromeHeight - 20

    /// Clear record between the chrome and where content starts, so the disc reads as the hero.
    private static let discReveal: CGFloat = 44

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
            .foregroundStyle(Color.white.opacity(navigationPillShowsBack ? 0.85 : 0.45))
            .disabled(!navigationPillShowsBack)
            .help("Back")

            Rectangle()
                .fill(Color.cisumChromeSubtle)
                .frame(width: 1, height: 15)

            Image(systemName: "chevron.right")
                .frame(width: 20, height: 32)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.cisumPrimaryText)
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
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? Color.cisumPrimaryText : Color.cisumPrimaryText.opacity(0.7))
                        .frame(width: 60, height: 37)
                        .background {
                            if isActive {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.1))
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
        case .library: "rectangle.stack"
        case .search: "magnifyingglass"
        }
    }

    /// Whether the current tab has somewhere to go back to.
    private var navigationPillShowsBack: Bool {
        (navigationState.tabPaths[navigationState.selectedTab]?.count ?? 0) > 0
    }

    private var navigationPillSurface: some View {
        let shape = Capsule(style: .continuous)
        return // Dark material, not Liquid Glass: `glassEffect` (plain or tinted) resolved to a light grey
        // here, which washed out the white text on it.
        shape.fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        // Same scrim as the sidebar and the transport, so all three floating surfaces sit at
        // one key instead of the pill reading lighter than the bar directly above it.
        .overlay {
            shape.fill(Color.black.opacity(0.2))
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        // Glass catches light along its top edge.
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
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

#if os(iOS)
/// Opens the iOS 26 zoom cover when a song is tapped anywhere, and collapses the shared state when
/// the cover is dismissed.
///
/// A separate view on purpose: only this body observes `isExpanded`, so a song tap re-evaluates
/// this empty view and not RootView — re-evaluating RootView destroys the zoom's
/// `matchedTransitionSource` identity. On iOS 17/18 it does nothing; the overlay window owns the
/// player there.
private struct ZoomCoverBridge: View {
    let presentation: PlayerPresentationController
    @Binding var isCoverPresented: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .onChange(of: presentation.isExpanded) { _, expanded in
                    if expanded, !isCoverPresented { isCoverPresented = true }
                }
                .onChange(of: isCoverPresented) { _, presented in
                    if !presented { presentation.collapse() }
                }
        }
    }
}
#endif

#if os(macOS)
/// Folds the sidebar away or brings it back.
private struct SidebarToggle: View {
    let navigationState: NavigationState

    var body: some View {
        Button {
            navigationState.isSidebarCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.cisumSecondaryText)
                .frame(width: 20, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(navigationState.isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")
    }
}

/// With the sidebar folded away its traffic lights go with it, so they and the way back to the
/// sidebar sit at the content's top-left corner instead.
///
/// Its own view so it reads `isSidebarCollapsed` itself: the content column is a separate hosting
/// controller, and a check made in RootView's body was frozen at its first value.
private struct CollapsedSidebarControls: View {
    let navigationState: NavigationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if navigationState.isSidebarCollapsed {
                HStack(spacing: 16) {
                    WindowControls()
                    SidebarToggle(navigationState: navigationState)
                }
                .padding(.leading, 14)
                .padding(.top, 14)
                // Arrive from where the sidebar went, a beat after it has gone. Leave at once: the
                // returning sidebar brings its own controls, and a fade showed two sets at once.
                .transition(
                    .asymmetric(
                        insertion: (reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: -12)))
                            .animation(MacSplitView.sidebarAnimation.delay(reduceMotion ? 0 : 0.1)),
                        removal: .identity
                    )
                )
            }
        }
        .animation(MacSplitView.sidebarAnimation, value: navigationState.isSidebarCollapsed)
    }
}
#endif

