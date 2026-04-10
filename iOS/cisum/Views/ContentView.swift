//
//  ContentView.swift
//  cisum
//
//  Created by Aarav Gupta on 29/11/25.
//

import SwiftUI
import YouTubeSDK

struct ContentView: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.router) private var router

    @State private var isScrollingDown = false
    @State private var storedOffset: CGFloat = 0
    @State var scrollPhase: ScrollPhases = .idle
    @State var tabBarVisibility: Visibility = .visible
    
    @State private var expandMiniPlayer: Bool = false
    @Namespace private var playerAnimationNamespace
    
    let hideThresholds: CGFloat = 40
    let showThresholds: CGFloat = -10
    
    @Namespace private var namespace
    
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        iOSTabView(
            selection: selectedTabBinding,
            expandMiniPlayer: $expandMiniPlayer,
            playerAnimationNamespace: playerAnimationNamespace,
            searchText: Bindable(searchViewModel).searchText
        ) {
            Tab("Home", systemImage: "house.fill", value: TabItem.home) {
                tabRoot(for: .home) {
                    HomeView()
                }
            }
            
            Tab("Discover", systemImage: "globe", value: TabItem.discover) {
                tabRoot(for: .discover) {
                    DiscoverView()
                }
            }
            
            Tab("Library", systemImage: "music.note.list", value: TabItem.library) {
                tabRoot(for: .library) {
                    LibraryView()
                }
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: TabItem.search, role: .search) {
                tabRoot(for: .search) {
                    SearchView()
                }
            }
        } onSearchSubmit: {
            searchViewModel.performDebouncedSearch()
        }
        .tabbarBottomViewAccessory {
            DynamicPlayerIsland(
                isPlayerExpanded: $expandMiniPlayer,
                namespace: playerAnimationNamespace
            )
        }
        .tabbarVisibility(tabBarVisibility)
        .animation(.smooth(duration: 0.3), value: tabBarVisibility)
        .environment(\.playerPresentationActions, playerPresentationActions)
        .systemVolumeController(SystemVolumeController.shared, showsSystemVolumeHUD: false)
        .onChange(of: router.selectedTab) { _, _ in
            if tabBarVisibility != .visible {
                tabBarVisibility = .visible
            }
        }
        .enableInjection()
    }
}

#Preview {
    ContentView()
        .environment(PlayerViewModel())
        .environment(SearchViewModel())
        .environment(PrefetchSettings.shared)
        .environment(NetworkPathMonitor.shared)
    .environment(\.router, Router())
    .environment(\.youtube, YouTube.shared)
}

private extension ContentView {
    var selectedTabBinding: Binding<TabItem> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectedTab = $0 }
        )
    }

    var playerPresentationActions: PlayerPresentationActions {
        PlayerPresentationActions(
            expand: {
                expandPlayer()
            },
            collapse: {
                collapsePlayer()
            },
            toggle: {
                togglePlayerExpansion()
            }
        )
    }

    func expandPlayer() {
        guard !expandMiniPlayer else { return }
        withAnimation(.playerExpandAnimation) {
            expandMiniPlayer = true
        }
    }

    func collapsePlayer() {
        guard expandMiniPlayer else { return }
        withAnimation(.playerExpandAnimation) {
            expandMiniPlayer = false
        }
    }

    func togglePlayerExpansion() {
        if expandMiniPlayer {
            collapsePlayer()
        } else {
            expandPlayer()
        }
    }

    func tabRoot<Content: View>(for tab: TabItem, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            content()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onScrollOffsetChange { oldValue, newValue in
                    let scrollingDown = oldValue < newValue
                    
                    if self.isScrollingDown != scrollingDown {
                        let adjustedOffset = newValue - (tabBarVisibility == .hidden ? 20 : 0)
                        if storedOffset != adjustedOffset {
                            storedOffset = adjustedOffset
                        }
                        self.isScrollingDown = scrollingDown
                    }
                    
                    let diff = newValue - storedOffset
                    if scrollPhase == .interacting {
                        if diff > hideThresholds {
                            if tabBarVisibility != .hidden {
                                tabBarVisibility = .hidden
                            }
                        } else if diff < showThresholds {
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
                .usingRouter()
        }
    }
}
