//
//  iOSTabView.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

import SwiftUI

struct iOSTabView<SelectionValue: Hashable>: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.tabBarBottomAccessory) private var tabBarBottomAccessory
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var selection: SelectionValue
    let tabs: [TabViewData<SelectionValue>]
    
    @State private var showMiniPlayer: Bool = false
    @Binding var expandMiniPlayer: Bool
    var playerAnimationNamespace: Namespace.ID

    var searchText: Binding<String>
    var onSearchSubmit: () -> Void
    
    init(
        selection: Binding<SelectionValue>,
        expandMiniPlayer: Binding<Bool>,
        playerAnimationNamespace: Namespace.ID,
        searchText: Binding<String> = .constant(""),
        @TabViewBuilder<SelectionValue> content: () -> [TabViewData<SelectionValue>],
        onSearchSubmit: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self._expandMiniPlayer = expandMiniPlayer
        self.playerAnimationNamespace = playerAnimationNamespace
        self.tabs = content()
        self.searchText = searchText
        self.onSearchSubmit = onSearchSubmit
    }
    
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    private var popupItemID: String {
        playerViewModel.currentVideoId ?? "cisum-now-playing"
    }

    var body: some View {
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
                    .overlay {
                        ExpandablePlayer(
                            show: .constant(true),
                            isExpanded: $expandMiniPlayer,
                            collapsedFrame: .zero
                        )
                        // Hack to fix the status bar color not updating correctly in iOS 26
                        .toolbarColorScheme(colorScheme, for: .navigationBar)
                    }
            } else {
                iOS26TabView
                    .universalOverlay(show: .constant(true)) {
                        ExpandablePlayer(
                            show: .constant(true),
                            isExpanded: $expandMiniPlayer,
                            collapsedFrame: .zero
                        )
                        .ignoresSafeArea(.keyboard)
                    }
            }
        }
        .enableInjection()
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
        ZStack {
            ZStack {
                if let searchTab = tabs.first(where: { $0.role == .search }),
                   selection == searchTab.value {
                    searchTab.content
                } else {
                    ForEach(tabs.filter { $0.role != .search }) { tab in
                        if selection == tab.value {
                            tab.content
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomTabBar
        }
    }

    @ViewBuilder
    private var bottomTabBar: some View {
        VStack(spacing: 6) {
            if tabBarVisibility == .visible {
                iOS26TabBar(
                    tabs: tabs,
                    activeTab: $selection,
                    showsSearchBar: tabs.contains(where: { $0.role == .search }),
                    searchText: searchText,
                    onSearchTriggered: {
                        if let searchTab = tabs.first(where: { $0.role == .search }) {
                            selection = searchTab.value
                        }
                    },
                    onSearchSubmitted: onSearchSubmit
                )
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .padding(.bottom, tabBarVisibility == .hidden ? -20 : 4)
        .allowsHitTesting(tabBarVisibility != .hidden)
        .animation(.smooth(duration: 0.3), value: tabBarVisibility)
    }
}
