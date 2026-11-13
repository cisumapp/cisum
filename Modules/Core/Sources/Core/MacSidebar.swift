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
    /// Library rows the user hid with Edit, by title. ponytail: a comma list in AppStorage; a
    /// Set type is not storable there and the titles never contain commas.
    @AppStorage("macSidebarHiddenRows") private var hiddenRows = ""
    /// The section whose rows are being chosen with Edit, if any.
    @State private var editingSection: String?

    var body: some View {
        List {
            row(.tab(.search), "Search", "magnifyingglass")
            row(.tab(.home), "Home", "house")
            row(.tab(.discover), "Discover", "square.grid.2x2")

            Section {
                if isLibraryExpanded {
                    if editingSection == "Library" {
                        ForEach(Self.libraryRows, id: \.title) { item in
                            editRow(item.title, item.symbol)
                        }
                    } else {
                        ForEach(Self.libraryRows, id: \.title) { item in
                            if !isHidden(item.title) {
                                row(item.item, item.title, item.symbol)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Library", isExpanded: $isLibraryExpanded)
            }

            Section {
                if isPlaylistsExpanded {
                    if editingSection == "Playlists" {
                        editRow("All Playlists", "music.note.list")
                        editRow("Saved", "star.fill")
                    } else {
                        playlistRows
                    }
                }
            } header: {
                sectionHeader("Playlists", isExpanded: $isPlaylistsExpanded)
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

    /// The user's playlists, after All Playlists and Saved.
    @ViewBuilder
    private var playlistRows: some View {
        if !isHidden("All Playlists") {
            row(.page(.libraryPlaylists), "All Playlists", "music.note.list")
        }
        if !isHidden("Saved"), let saved = playlists.first(where: { $0.playlistID == PlaylistLibraryStore.savedPlaylistID }) {
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
            .selectable(.playlist(playlist.playlistID), selection: $selection)
        }
    }

    private static let libraryRows: [(item: SidebarItem, title: String, symbol: String)] = [
        (.tab(.library), "Recently Added", "clock.arrow.circlepath"),
        (.page(.librarySongs), "Songs", "music.note"),
        (.page(.libraryArtists), "Artists", "music.microphone"),
        (.page(.libraryAlbums), "Albums", "square.stack"),
    ]

    /// The design's section header: the title, then Edit — which turns the section's rows into
    /// checkboxes for choosing which show, as Apple Music's sidebar does — and a chevron that folds
    /// the section. Plain buttons: a pop-up menu here took the whole header's hit area and the
    /// chevron could not be clicked.
    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        let isEditing = editingSection == title
        return HStack(spacing: 6) {
            Text(title)
            Spacer()
            Button(isEditing ? "Done" : "Edit") {
                withAnimation(.snappy(duration: 0.2)) {
                    editingSection = isEditing ? nil : title
                    if !isEditing { isExpanded.wrappedValue = true }
                }
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded.wrappedValue ? "Collapse" : "Expand")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.cisumSecondaryText)
    }

    /// A row while its section is being edited: a checkbox for whether it shows.
    private func editRow(_ title: String, _ symbol: String) -> some View {
        let shown = shownBinding(title)
        // A button rather than a checkbox Toggle: a sidebar List did not draw the Toggle rows.
        return Button {
            shown.wrappedValue.toggle()
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: shown.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(shown.wrappedValue ? Color.cisumPrimaryText : Color.cisumSecondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func isHidden(_ title: String) -> Bool {
        hiddenRows.split(separator: ",").contains { $0 == title }
    }

    private func shownBinding(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !isHidden(title) },
            set: { shown in
                var hidden = hiddenRows.split(separator: ",").map(String.init).filter { $0 != title }
                if !shown { hidden.append(title) }
                hiddenRows = hidden.joined(separator: ",")
            }
        )
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .selectable(item, selection: $selection)
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

private extension View {
    /// A row the user picks by clicking, with the design's quiet white wash when chosen. The List
    /// has no `selection:` because AppKit draws that highlight in the app's accent (a red pill)
    /// whatever `.tint` says.
    func selectable(_ item: SidebarItem, selection: Binding<SidebarItem?>) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { selection.wrappedValue = item }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(selection.wrappedValue == item ? 0.1 : 0))
                    .padding(.horizontal, 10)
            )
    }
}
#endif
