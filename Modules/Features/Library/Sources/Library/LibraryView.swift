import Aesthetics
import Authentication
import Kingfisher
import Models
import Playlists
import SwiftData
import SwiftUI
import Utilities

/// The user's Library: their playlists, and the songs, albums and artists in them.
///
/// Only playlists put anything here — imported, created, Saved or shared. Songs, albums and
/// artists are worked out from those playlists' tracks (`LibraryIndex`), so searching or playing
/// something never adds it.
public struct LibraryView: View {
    public init() {}

    @Environment(SpotifySessionCoordinator.self) private var spotifyCoordinator
    @Environment(\.router) private var router
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    @Environment(\.importDownloadManager) private var importDownloadManager
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var allPlaylists: [Playlist]
    @Query private var items: [PlaylistItem]

    @State private var index = LibraryIndex(items: [])
    #if os(iOS)
    /// Only `NavigationBarView` reads this; the macOS chrome ignores scroll position.
    @State private var scrollOffset: CGFloat = 0
    #endif
    @State private var isPresentingImport = false
    @State private var isPresentingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isSyncingLikedSongs = false
    @State private var errorMessage: String?

    public var body: some View {
        #if os(iOS)
        NavigationBarView(
            title: "Library",
            scrollOffset: $scrollOffset,
            customActions: [
                ProfileMenuCustomAction(title: "New Playlist") { isPresentingNewPlaylist = true },
                ProfileMenuCustomAction(title: "Import Playlist") { isPresentingImport = true },
            ]
        ) {
            content
        }
        #else
        // `NavigationBarView` is built on UIKit, so macOS supplies its own scroll view.
        ScrollView {
            content
                .contentMargins(.top, 8)
        }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            if playlists.isEmpty, savedPlaylist == nil {
                emptyState
            } else {
                categories
                if !recentlyAdded.isEmpty {
                    recentlyAddedGrid
                }
            }
        }
        .padding(.horizontal)
        #if os(iOS)
        // Clears the floating mini player.
        .safeAreaPadding(.bottom, 140)
        #endif
        .sheet(isPresented: $isPresentingImport) {
            ImportServiceSheet()
        }
        .alert("New Playlist", isPresented: $isPresentingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") { createLocalPlaylist() }
        }
        .alert("Library Action Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // ponytail: rebuilt when the item count changes; an edit to an item's metadata shows on
        // the next add or delete. Key on a checksum of updatedAt if that ever matters.
        .task(id: items.count) {
            index = LibraryIndex(items: items)
        }
    }

    // MARK: - Data

    /// Every playlist but Saved, which has its own row.
    private var playlists: [Playlist] {
        allPlaylists.filter { $0.playlistID != PlaylistLibraryStore.savedPlaylistID }
    }

    private var savedPlaylist: Playlist? {
        allPlaylists.first { $0.playlistID == PlaylistLibraryStore.savedPlaylistID }
    }

    private var recentlyAdded: [Playlist] {
        Array(playlists.sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }.prefix(12))
    }

    /// Spotify Liked Songs, offered while Spotify is connected and they are not imported yet.
    private var canImportLikedSongs: Bool {
        spotifyCoordinator.isAuthenticated
            && !playlists.contains { $0.sourcePlaylistID == SpotifyImportService.likedSongsPlaylistID }
    }

    // MARK: - Sections

    private var categories: some View {
        VStack(spacing: 0) {
            if !playlists.isEmpty || canImportLikedSongs {
                NavigationLink {
                    LibraryPlaylistsView(
                        playlists: playlists,
                        likedSongs: canImportLikedSongs ? .init(isSyncing: isSyncingLikedSongs) { Task { await openLikedSongs() } } : nil,
                        onDelete: deletePlaylist,
                        onReimport: reimport
                    )
                } label: {
                    LibraryCategoryRow(title: "Playlists", systemImage: "music.note.list", count: playlists.count)
                }
            }

            if !index.songs.isEmpty {
                NavigationLink {
                    LibrarySongsView(songs: index.songs)
                } label: {
                    LibraryCategoryRow(title: "Songs", systemImage: "music.note", count: index.songs.count)
                }
            }

            if !index.albums.isEmpty {
                NavigationLink {
                    LibraryAlbumsView(albums: index.albums)
                } label: {
                    LibraryCategoryRow(title: "Albums", systemImage: "square.stack", count: index.albums.count)
                }
            }

            if !index.artists.isEmpty {
                NavigationLink {
                    LibraryArtistsView(artists: index.artists)
                } label: {
                    LibraryCategoryRow(title: "Artists", systemImage: "music.mic", count: index.artists.count)
                }
            }

            if let savedPlaylist {
                Button {
                    router.navigate(to: .playlist(id: savedPlaylist.playlistID))
                } label: {
                    LibraryCategoryRow(title: "Saved", systemImage: "star", count: savedPlaylist.itemCount)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recentlyAddedGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Added")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                ForEach(recentlyAdded, id: \.playlistID) { playlist in
                    Button {
                        router.navigate(to: .playlist(id: playlist.playlistID))
                    } label: {
                        LibraryTile(
                            url: playlist.artworkURLString.flatMap(URL.init(string:)),
                            symbol: "music.note.list",
                            title: playlist.title,
                            subtitle: playlist.sourceProvider?.libraryName ?? "Playlist"
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { deletePlaylist(playlist) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your Library is empty")
                .font(.title3.bold())
            Text("Import playlists from Spotify, YouTube or Apple Music, or make your own. Their songs, albums and artists show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Import Playlist") { isPresentingImport = true }
                    .buttonStyle(.borderedProminent)
                Button("New Playlist") { isPresentingNewPlaylist = true }
                    .buttonStyle(.bordered)
            }
            .tint(.primary)
            if canImportLikedSongs {
                Button(isSyncingLikedSongs ? "Importing Liked Songs…" : "Import Spotify Liked Songs") {
                    Task { await openLikedSongs() }
                }
                .disabled(isSyncingLikedSongs)
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Actions

    private func deletePlaylist(_ playlist: Playlist) {
        LibraryActions.delete(playlist, store: playlistLibraryStore)
    }

    private func reimport(_ playlist: Playlist) {
        LibraryActions.reimport(playlist, importer: importDownloadManager)
    }

    /// Imports Spotify Liked Songs through the shared import pipeline, then opens them.
    private func openLikedSongs() async {
        guard let importDownloadManager else { return }
        isSyncingLikedSongs = true
        defer { isSyncingLikedSongs = false }
        let likedSongs = ImportablePlaylistRef(id: SpotifyImportService.likedSongsPlaylistID, title: "Liked Songs")
        guard let playlistID = await importDownloadManager.importAndWait(provider: .spotify, playlistRef: likedSongs) else {
            errorMessage = "Couldn't import your Spotify Liked Songs. Check that Spotify is connected."
            return
        }
        router.navigate(to: .playlist(id: playlistID))
    }

    private func createLocalPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, let playlistLibraryStore else { return }
        Task {
            let id = await playlistLibraryStore.createLocalPlaylist(title: name)
            router.navigate(to: .playlist(id: id))
        }
    }
}

/// A row on the Library's front page: icon, name, count, chevron.
private struct LibraryCategoryRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.cisumYellow)
                .frame(width: 28)
            Text(title)
                .font(.title3)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            // A Rectangle, not a Divider: inside an overlay a Divider takes the row's HStack axis
            // and draws vertically.
            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 0.5)
                .padding(.leading, 42)
        }
    }
}
