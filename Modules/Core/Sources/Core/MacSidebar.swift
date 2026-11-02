//
//  MacSidebar.swift
//  Core
//
//  The macOS sidebar: the tabs, then the Library's pages, then the user's playlists.
//

#if os(macOS)
import Aesthetics
import Models
import Playlists
import SwiftData
import SwiftUI
import Utilities

/// A row in the sidebar and what selecting it opens.
enum SidebarItem: Hashable {
    /// A tab's root.
    case tab(TabItem)
    /// A page pushed onto the Library tab.
    case page(AppRoute)
    /// A playlist, opened in the Library tab.
    case playlist(String)
}

/// The sidebar's rows, grouped the way the design groups them: where to go, the Library, and
/// the user's playlists — each playlist one click away rather than two pages deep.
struct MacSidebar: View {
    let navigationState: NavigationState

    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]
    @State private var selection: SidebarItem? = .tab(.home)
    @State private var isLibraryExpanded = true
    @State private var isPlaylistsExpanded = true

    var body: some View {
        List(selection: $selection) {
            row(.tab(.search), "Search", "magnifyingglass")
            row(.tab(.home), "Home", "house")
            row(.tab(.discover), "Discover", "square.grid.2x2")

            Section("Library", isExpanded: $isLibraryExpanded) {
                row(.tab(.library), "Recently Added", "clock.arrow.circlepath")
                row(.page(.librarySongs), "Songs", "music.note")
                row(.page(.libraryArtists), "Artists", "music.microphone")
                row(.page(.libraryAlbums), "Albums", "square.stack")
            }

            Section("Playlists", isExpanded: $isPlaylistsExpanded) {
                row(.page(.libraryPlaylists), "All Playlists", "music.note.list")
                if let saved = playlists.first(where: { $0.playlistID == PlaylistLibraryStore.savedPlaylistID }) {
                    row(.playlist(saved.playlistID), "Saved", "star.fill")
                }
                ForEach(playlists.filter { $0.playlistID != PlaylistLibraryStore.savedPlaylistID }, id: \.playlistID) { playlist in
                    Label {
                        Text(playlist.title)
                    } icon: {
                        ArtworkImage(url: playlist.artworkURLString.flatMap(URL.init(string:)), size: 16)
                            .frame(width: 16, height: 16)
                            .background(Color.cisumChromeSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                    .tag(SidebarItem.playlist(playlist.playlistID))
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, item in
            if let item { open(item) }
        }
        // A tab chosen elsewhere (the tab pill, a deep link) moves the highlight with it.
        .onChange(of: navigationState.selectedTab) { _, tab in
            if selection.map({ owningTab(of: $0) }) != tab {
                selection = .tab(tab)
            }
        }
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .tag(item)
    }

    private func owningTab(of item: SidebarItem) -> TabItem {
        switch item {
        case let .tab(tab): tab
        case .page, .playlist: .library
        }
    }

    /// Shows the item: a tab at its root, or a Library page or playlist as the only page on the
    /// Library tab's stack, so the back button returns to the Library rather than to whatever
    /// was open before.
    private func open(_ item: SidebarItem) {
        switch item {
        case let .tab(tab):
            navigationState.tabPaths[tab] = NavigationPath()
            navigationState.selectedTab = tab
        case let .page(route):
            navigationState.tabPaths[.library] = NavigationPath([route])
            navigationState.selectedTab = .library
        case let .playlist(id):
            navigationState.tabPaths[.library] = NavigationPath([AppRoute.playlist(id: id)])
            navigationState.selectedTab = .library
        }
    }
}
#endif
