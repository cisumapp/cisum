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
        .environment(\.isSearchExpanded, $isSearchExpanded)
        .onAppear {
            isSearchExpanded = isSearchTabSelection(selection)
            // Seed the store immediately so ExpandablePlayer has valid offsets
            // even before the first layout pass on iOS 26 (where bottomTabBar isn't called).
            if #available(iOS 26.0, *) {
                let w = UIScreen.main.bounds.width
                let sa = (UIApplication.shared.connectedScenes.first as? UIWindowScene)
                    .flatMap { $0.windows.first(where: \.isKeyWindow) }
                    .map { $0.safeAreaInsets.bottom } ?? 0
                let hasSearch = tabs.contains { $0.role == .search }
                let phase: ResponsiveLayout.AccessoryPhase = hasSearch ? .inlineWithSearch : .inline
                // tabBarHeight = 0 → uses measured iOS 26 constant (91 pt)
                TabBarStateStore.shared.accessoryOffsets = .init(
                    phase: phase, screenWidth: w, safeAreaBottom: sa
                )
            }
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
                if let searchTab = tabs.first(where: { $0.role == .search }),
                   selection == searchTab.value {
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

        let phase: ResponsiveLayout.AccessoryPhase = {
            let hasSearch = tabs.contains { $0.role == .search }
            if tabBarVisibility == .visible {
                return hasSearch ? .inlineWithSearch : .inline
            } else {
                return hasSearch ? .expandedWithSearch : .expanded
            }
        }()
        let offsets = ResponsiveLayout.AccessoryOffsets(
            phase: phase,
            screenWidth: screenW,
            safeAreaBottom: safeBottom,
            tabBarHeight: customTabBarHeight,  // triggers iOS 17/18 formula
            isSearchExpanded: isSearchExpanded
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
        // Defer the store write to after the view is committed.
        // Writing an @Observable property directly during body evaluation
        // triggers "AttributeGraph: setting value during update" and can crash.
        .task(id: offsets) {
            TabBarStateStore.shared.accessoryOffsets = offsets
        }
    }
}
#endif
