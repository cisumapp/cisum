//
//  ContentView.swift
//  cisum
//
//  Created by Aarav Gupta on 18/03/26.
//

import SwiftUI
import YouTubeSDK

struct ContentView: View {
    @Environment(\.router) private var router
    @Environment(\.youtube) private var youtube
    @Environment(SearchOverlayController.self) private var searchOverlay

    @State private var sidebarState: SidebarState = .collapsed
    @State private var sidebarExpandedWidth: CGFloat = 232
    
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        //        ResizableSidebar(
        //            sidebarState: $sidebarState,
        //            expandedWidth: $sidebarExpandedWidth,
        //            collapsedWidth: 64,
        //            minExpandedWidth: 210,
        //            maxExpandedWidth: 420,
        //            sidebarPadding: 8
        //        ) { presentationState, sidebarWidth in
        //            SidebarView(
        //                sidebarState: $sidebarState,
        //                presentationState: presentationState
        //            )
        //            .frame(width: sidebarWidth)
        //            .frame(maxHeight: .infinity)
        //        } mainContent: { leadingInset in
        //            tabSurface
        //                .onPreferenceChange(SearchOverlayContextPreferenceKey.self) { newContext in
        //                    searchOverlay.updateContext(newContext)
        //                }
        //                .padding(.leading, leadingInset)
        //                .padding(.trailing, 8)
        //                .padding(.vertical, 8)
        //                .animation(.sidebarExpandAnimation, value: leadingInset)
        //        } dynamicIslandPlayer: {
        //            DynamicPlayerIsland()
        //        }
        tabSurface
            .onPreferenceChange(SearchOverlayContextPreferenceKey.self) { newContext in
                searchOverlay.updateContext(newContext)
            }
            .overlay(alignment: .topLeading) {
                ProfileButton()
                    .padding(8)
            }
            .overlay(alignment: .top) {
                SearchOverlayBar()
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                DynamicPlayerIsland()
                    .padding(8)
            }
            .background {
                backgroundFill
            }
            .ignoresSafeArea()
            .enableInjection()
    }
}

#Preview {
    ContentView()
        .injectPreviewDependencies()
        .environment(SearchOverlayController())
}

private extension ContentView {
    @ViewBuilder
    var backgroundFill: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.92))
        }
    }

    @ViewBuilder
    var tabSurface: some View {
        tabRoot(for: router.selectedTab) {
            selectedTabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    var selectedTabContent: some View {
        switch router.selectedTab {
        case .home:
            HomeView(youtube: youtube)
        case .discover:
            DiscoverView()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        }
    }

    func tabRoot<Content: View>(for tab: TabItem, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .usingRouter()
        }
    }
}
