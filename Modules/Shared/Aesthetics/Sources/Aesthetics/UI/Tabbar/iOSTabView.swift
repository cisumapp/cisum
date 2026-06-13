//
//  iOSTabView.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

import SwiftUI

#if os(iOS)
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
    }

    // MARK: - TabView (iOS 17+)

    private var iOS26TabView: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            ZStack {
                if let searchTab = tabs.first(where: { $0.role == .search }),
                   selection == searchTab.value
                {
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
        let screenW = UIScreen.main.bounds.width
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
            safeAreaBottom: safeBottom
        )

        return ZStack(alignment: .bottom) {
            if let accessory = tabBarBottomAccessory {
                accessory
                    .frame(width: offsets.width, height: offsets.accessoryHeight)
                    .contentShape(.rect)
                    .onTapGesture {
                        expandMiniPlayer.toggle()
                    }
                    // Sit the accessory immediately above the tab bar (+ a small gap),
                    // then subtract the safe area so it's relative to the ZStack bottom.
                    .padding(.bottom, offsets.tabBarHeight + 8)
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: tabBarVisibility)
        .environment(\.tabBarAccessoryOffsets, offsets)
    }
}
#endif
