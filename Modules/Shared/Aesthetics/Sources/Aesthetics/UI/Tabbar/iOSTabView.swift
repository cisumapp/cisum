//
//  iOSTabView.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

import SwiftUI

#if os(iOS)
#if DEBUG
/// Namespace for debug-only feature flags that are not valid as static stored
/// properties on generic types.
public enum iOSTabViewDebug {
    /// When `true`, renders the custom tab bar overlaid on the native iOS 26
    /// bar so you can compare them pixel-for-pixel in the simulator.
    public nonisolated(unsafe) static var showBothTabBars: Bool = false
}
#endif

public struct iOSTabView<SelectionValue: Hashable, PlayerContent: View, MiniPlayerContent: View, ZoomedPlayerContent: View>: View {
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.tabBarBottomAccessory) private var tabBarBottomAccessory
    @Environment(\.colorScheme) private var colorScheme
    /// Drives the landscape axis of `AccessoryOffsets`. Size class changes in
    /// lockstep with layout, unlike UIScreen.main.bounds which lags rotation.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Binding var selection: SelectionValue
    let tabs: [TabViewData<SelectionValue>]

    @State private var showMiniPlayer: Bool = false
    @State private var isSearchExpanded: Bool = false
    @Binding var expandMiniPlayer: Bool
    /// Local state for the iOS 26 zoom cover presentation.  Using a local
    /// `@State` instead of the `expandMiniPlayer` binding avoids triggering
    /// `RootView.body` re-evaluation on tap, which would destroy the accessory
    /// view identity and break the `matchedTransitionSource` pairing.
    @State private var isCoverPresented = false
    var playerAnimationNamespace: Namespace.ID

    var searchText: Binding<String>
    var onSearchSubmit: () -> Void
    let playerContent: PlayerContent

    /// The mini player view, passed as a concrete type so SwiftUI can track it
    /// as the zoom transition source. (Reading from `tabBarBottomAccessory`
    /// environment yields `AnyView?` which breaks the matched-geometry pairing.)
    let miniPlayerContent: MiniPlayerContent

    /// The player presented in the iOS 26 zoom cover.
    let zoomedPlayerContent: ZoomedPlayerContent
    let popupItemID: String
    let accentColor: Color

    public init(
        selection: Binding<SelectionValue>,
        expandMiniPlayer: Binding<Bool>,
        playerAnimationNamespace: Namespace.ID,
        searchText: Binding<String> = .constant(""),
        playerContent: PlayerContent,
        miniPlayerContent: MiniPlayerContent,
        zoomedPlayerContent: ZoomedPlayerContent,
        popupItemID: String = "cisum-now-playing",
        accentColor: Color = .blue,
        @TabViewBuilder<SelectionValue> content: () -> [TabViewData<SelectionValue>],
        onSearchSubmit: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self._expandMiniPlayer = expandMiniPlayer
        self.playerAnimationNamespace = playerAnimationNamespace
        self.tabs = content()
        self.searchText = searchText
        self.onSearchSubmit = onSearchSubmit
        self.playerContent = playerContent
        self.miniPlayerContent = miniPlayerContent
        self.zoomedPlayerContent = zoomedPlayerContent
        self.popupItemID = popupItemID
        self.accentColor = accentColor
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                #if DEBUG
                if iOSTabViewDebug.showBothTabBars {
                    ZStack {
                        NativeTabView
                            .tabViewBottomAccessory {
                                miniPlayerContent
                                    .contentShape(.rect)
                                    .onTapGesture { isCoverPresented.toggle() }
                            }
                        iOS26TabView
                            .allowsHitTesting(false)
                            .opacity(0.6)
                    }
                } else {
                    NativeTabView
                        .tabViewBottomAccessory {
                            miniPlayerContent
                                .measureTabAccessoryGeometry()
                                .contentShape(.rect)
                                .highPriorityGesture(TapGesture().onEnded { isCoverPresented.toggle() })
                        }
                }
                #else
                NativeTabView
                    .tabViewBottomAccessory {
                        miniPlayerContent
                            .contentShape(.rect)
                            .highPriorityGesture(TapGesture().onEnded {
                                isCoverPresented.toggle()
                            })
                    }
                #endif
            } else {
                // iOS 17/18: the custom bar, with the player hosted in the detached overlay
                // window. The overlay used to wrap the whole Group, so it ran on iOS 26 too and
                // the player was presented twice over — once here and once by the accessory.
                iOS26TabView
                    .universalOverlay(show: .constant(true)) {
                        playerContent
                            .ignoresSafeArea(.keyboard)
                    }
            }
        }
        // iOS 26: the accessory IS the collapsed player, so tapping it presents the expanded one
        // as a cover that zooms out of it. No overlay window, no pan gesture, no window stacking —
        // the system provides the transition and its interactive swipe-down dismiss.
        //
        // Applied directly (not through a @ViewBuilder wrapper) so SwiftUI can track the
        // _ConditionalContent type for the zoom transition pairing.
        .fullScreenCover(isPresented: $isCoverPresented) {
            Group {
                if #available(iOS 18.0, *) {
                    zoomedPlayerContent
                        .navigationTransition(.zoom(sourceID: PlayerZoomID.miniPlayer, in: playerAnimationNamespace))
                } else {
                    zoomedPlayerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.isSearchExpanded, $isSearchExpanded)
        // Single publisher for both OS paths. Keyed so rotation, search, tab-bar
        // visibility and width changes each republish — the previous .onAppear seed
        // ran once, leaving the overlay on launch-time geometry forever.
        .task(id: accessoryPublishKey) {
            publishAccessoryOffsets()
        }
        .onAppear {
            isSearchExpanded = isSearchTabSelection(selection)
        }
        .onChange(of: selection) { _, newValue in
            let isSearchSelected = isSearchTabSelection(newValue)
            if isSearchExpanded != isSearchSelected {
                isSearchExpanded = isSearchSelected
            }
        }
    }

    private func isSearchTabSelection(_ value: SelectionValue) -> Bool {
        tabs.first(where: { $0.role == .search })?.value == value
    }

    // MARK: - Accessory geometry

    /// The accessory's current state, resolved from the main tree. The overlay
    /// window is a detached SwiftUI tree and never receives this environment,
    /// which is why the result is published through `TabBarStateStore`.
    private var accessoryState: ResponsiveLayout.AccessoryState {
        .init(
            orientation: verticalSizeClass == .compact ? .landscape : .portrait,
            placement: tabBarVisibility == .visible ? .inline : .minimized,
            searchActive: isSearchExpanded
        )
    }

    private var foregroundScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    /// Scene coordinate space tracks rotation in lockstep with layout.
    /// `UIScreen.main.bounds` lags it — that is what produced the corrupt
    /// bottom-431.5 sample while the geometry probe was being developed.
    private var currentScreenWidth: CGFloat {
        foregroundScene?.coordinateSpace.bounds.width ?? UIScreen.main.bounds.width
    }

    private var currentSafeAreaBottom: CGFloat {
        // windowLevel .normal skips the UniversalOverlay PassThroughWindow
        // (.statusBar + 1), whose insets are not the app's.
        let window = foregroundScene?.windows.first { $0.windowLevel == .normal }
            ?? foregroundScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    /// Composite key so rotation, search, tab-bar visibility *and* width changes
    /// (iPad multitasking) each retrigger the publish.
    private struct AccessoryPublishKey: Equatable {
        let state: ResponsiveLayout.AccessoryState
        let screenWidth: CGFloat
        let safeAreaBottom: CGFloat
    }

    private var accessoryPublishKey: AccessoryPublishKey {
        .init(
            state: accessoryState,
            screenWidth: currentScreenWidth,
            safeAreaBottom: currentSafeAreaBottom
        )
    }

    /// Written from `.task`, not during body evaluation — mutating `@Observable`
    /// state mid-update triggers "AttributeGraph: setting value during update".
    private func publishAccessoryOffsets() {
        let state = accessoryState
        let width = currentScreenWidth

        // iOS 26 uses the measured constants (tabBarHeight 0). The custom bar path
        // passes its real height so the accessory clears the hand-rolled bar.
        var tabBarHeight: CGFloat = 0
        if #unavailable(iOS 26.0) {
            tabBarHeight = 56 * ResponsiveLayout.DeviceSizeClass(width: width).scaleFactor(for: width)
        }

        TabBarStateStore.shared.accessoryState = state
        TabBarStateStore.shared.accessoryOffsets = .init(
            state: state,
            screenWidth: width,
            safeAreaBottom: currentSafeAreaBottom,
            tabBarHeight: tabBarHeight
        )
    }

    private var visibleTabs: [TabViewData<SelectionValue>] {
        tabs.filter { $0.role != .search }
    }

    // MARK: - Native TabView (iOS 26+)

    @available(iOS 26.0, *)
    private var NativeTabView: some View {
        SwiftUI.TabView(selection: $selection) {
            ForEach(tabs) { tab in
                SwiftUI.Tab(
                    tab.title,
                    systemImage: tab.icon,
                    value: tab.value,
                    role: tab.role?.toNative
                ) {
                    tab.content
                        .toolbarVisibility(tabBarVisibility, for: .tabBar)
                        .animation(.bouncy(duration: 0.3), value: tabBarVisibility)
                }
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
    }

    // MARK: - TabView (iOS 17+)

    private var iOS26TabView: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            ZStack {
                if let searchTab = tabs.first(where: { $0.role == .search }), selection == searchTab.value {
                    searchTab.content
                } else {
                    ForEach(visibleTabs) { tab in
                        if selection == tab.value {
                            tab.content
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomTabBar(safeBottom: safeBottom)
            }
        }
    }

    private func bottomTabBar(safeBottom: CGFloat) -> some View {
        // Use the true screen width — NOT a GeometryProxy inside the tab area.
        // A proxy here reports a reduced height and mis-detects the device.
        let screenW = UIScreen.main.bounds.width
        let screenScale = ResponsiveLayout.DeviceSizeClass(width: screenW).scaleFactor(for: screenW)
        // iOS26TabBar is always exactly 56 * screenScale tall (see iOS26TabBar.swift line 145).
        // Search expansion only changes internal layout, NOT the bar's outer frame.
        let customTabBarHeight: CGFloat = 56 * screenScale

        // Prefer the published value so both paths agree; fall back to a local
        // computation only before the first publish lands.
        let offsets = TabBarStateStore.shared.accessoryOffsets
            ?? ResponsiveLayout.AccessoryOffsets(
                state: accessoryState,
                screenWidth: screenW,
                safeAreaBottom: safeBottom,
                tabBarHeight: customTabBarHeight // triggers iOS 17/18 formula
            )

        return ZStack(alignment: .bottom) {
            if #available(iOS 26.0, *) {
                if let accessory = tabBarBottomAccessory {
                    accessory
                        .frame(width: offsets.width, height: offsets.accessoryHeight)
                        .contentShape(.rect)
                        .onTapGesture {
                            expandMiniPlayer.toggle()
                        }
                        // `bottomInsetFromSafeArea` converts the screen-bottom-relative
                        // measured offset (91/21 pt) into a padding value relative to the
                        // safeAreaInset boundary so the pill lands in the correct position.
                        .padding(.bottom, offsets.bottomInsetFromSafeArea)
                        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: offsets.bottomOffset)
                }
            }

            if tabBarVisibility == .visible {
                iOS26TabBar(
                    tabs: tabs,
                    activeTab: $selection,
                    showsSearchBar: true,
                    accentColor: accentColor,
                    searchText: searchText,
                    onSearchTriggered: {
                        if let searchTab = tabs.first(where: { $0.role == .search }) {
                            selection = searchTab.value
                        }
                    },
                    onSearchSubmitted: {
                        onSearchSubmit()
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
            }
        }
        // Spring feels more natural than easeInOut when the bar snaps in/out.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: tabBarVisibility)
        .environment(\.tabBarAccessoryOffsets, offsets)
        // The store write lives on the single publisher in `body` — see the
        // .task(id: accessoryPublishKey) there. Duplicating it here would race it.
    }
}
#endif
