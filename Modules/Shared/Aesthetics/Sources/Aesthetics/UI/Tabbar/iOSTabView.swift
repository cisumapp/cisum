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

public struct iOSTabView<SelectionValue: Hashable, PlayerContent: View>: View {
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
    var playerAnimationNamespace: Namespace.ID

    var searchText: Binding<String>
    var onSearchSubmit: () -> Void
    let playerContent: PlayerContent
    let popupItemID: String
    let accentColor: Color

    public init(
        selection: Binding<SelectionValue>,
        expandMiniPlayer: Binding<Bool>,
        playerAnimationNamespace: Namespace.ID,
        searchText: Binding<String> = .constant(""),
        playerContent: PlayerContent,
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
        self.popupItemID = popupItemID
        self.accentColor = accentColor
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                #if DEBUG
                if iOSTabViewDebug.showBothTabBars {
                    // Side-by-side debug: native bar underneath, custom bar on top (non-interactive)
                    ZStack {
                        NativeTabView
                            .tabViewBottomAccessory {
                                if let accessory = tabBarBottomAccessory {
                                    accessory
                                        .contentShape(.rect)
                                        .onTapGesture { expandMiniPlayer.toggle() }
                                }
                            }
                        iOS26TabView
                            .allowsHitTesting(false)
                            .opacity(0.6)
                    }
                } else {
                    NativeTabView
                        .tabViewBottomAccessory {
                            if let accessory = tabBarBottomAccessory {
                                accessory
                                    .measureTabAccessoryGeometry()
                                    .contentShape(.rect)
                                    .onTapGesture { expandMiniPlayer.toggle() }
                            }
                        }
                }
                #else
                NativeTabView
                    .tabViewBottomAccessory {
                        if let accessory = tabBarBottomAccessory {
                            accessory
                                .contentShape(.rect)
                                .onTapGesture {
                                    expandMiniPlayer.toggle()
                                }
                        }
                    }
                #endif
            } else {
                iOS26TabView
            }
        }
        .universalOverlay(show: .constant(true)) {
            playerContent
                .ignoresSafeArea(.keyboard)
        }
        #if DEBUG
        .tabBarGeometryHUD()
        #endif
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
