//
//  LibraryCollections.swift
//  Library
//
//  The pages behind the Library's rows: Playlists, Songs, Albums and Artists.
//

import Aesthetics
import Kingfisher
import Models
import Playlists
import SwiftData
import SwiftUI
import Utilities

// MARK: - Entry point

/// One Library page on its own, for places outside the Library tab — the macOS sidebar links
/// straight to these. Reads its own data, so callers pass only which page.
public struct LibraryPage: View {
    public enum Kind: Hashable, Sendable {
        case songs, albums, artists, playlists
    }

    let kind: Kind

    @Query private var items: [PlaylistItem]
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var allPlaylists: [Playlist]
    @Environment(\.playlistLibraryStore) private var store
    @Environment(\.importDownloadManager) private var importer

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        switch kind {
        case .songs:
            LibrarySongsView(songs: LibraryIndex(items: items).songs)
        case .albums:
            LibraryAlbumsView(albums: LibraryIndex(items: items).albums)
        case .artists:
            LibraryArtistsView(artists: LibraryIndex(items: items).artists)
        case .playlists:
            LibraryPlaylistsView(
                playlists: allPlaylists.filter { $0.playlistID != PlaylistLibraryStore.savedPlaylistID },
                likedSongs: nil,
                onDelete: { LibraryActions.delete($0, store: store) },
                onReimport: { LibraryActions.reimport($0, importer: importer) }
            )
        }
    }
}

@MainActor
enum LibraryActions {
    static func delete(_ playlist: Playlist, store: PlaylistLibraryStore?) {
        let id = playlist.playlistID
        Task { await store?.deletePlaylist(playlistID: id) }
    }

    /// Fetches a service playlist again, in the background, into the same Library playlist.
    static func reimport(_ playlist: Playlist, importer: ImportDownloadManager?) {
        guard let provider = playlist.sourceProvider?.importProvider,
              let sourceID = playlist.sourcePlaylistID,
              let importer
        else { return }
        let ref = ImportablePlaylistRef(id: sourceID, title: playlist.title)
        Task { _ = await importer.enqueue(provider: provider, playlistRef: ref) }
    }
}

// MARK: - Playlists

struct LibraryPlaylistsView: View {
    /// The Spotify Liked Songs entry, while they are not imported yet.
    struct LikedSongs {
        let isSyncing: Bool
        let open: () -> Void
    }

    enum Sort: String, CaseIterable {
        case recent = "Recently Added"
        case title = "Title"
    }

    let playlists: [Playlist]
    let likedSongs: LikedSongs?
    let onDelete: (Playlist) -> Void
    let onReimport: (Playlist) -> Void

    @Environment(\.router) private var router
    @State private var source: PlaylistSource?
    @State private var sort = Sort.recent

    var body: some View {
        List {
            if sources.count > 1 {
                sourceFilter
                    .libraryRow()
            }

            if let likedSongs, source == nil || source == .spotify {
                Button(action: likedSongs.open) {
                    LibraryListRow(
                        artwork: LibraryArtwork(url: nil, symbol: "heart.fill"),
                        title: "Liked Songs",
                        subtitle: likedSongs.isSyncing ? "Importing from Spotify…" : "Import from Spotify"
                    )
                }
                .disabled(likedSongs.isSyncing)
                .libraryRow()
            }

            ForEach(shown, id: \.playlistID) { playlist in
                Button {
                    router.navigate(to: .playlist(id: playlist.playlistID))
                } label: {
                    LibraryListRow(
                        artwork: LibraryArtwork(url: playlist.artworkURLString.flatMap(URL.init(string:)), symbol: "music.note.list"),
                        title: playlist.title,
                        subtitle: subtitle(for: playlist)
                    )
                }
                .libraryRow()
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(playlist) }
                }
                .contextMenu {
                    if playlist.sourceProvider?.importProvider != nil, playlist.sourcePlaylistID != nil {
                        Button("Import Again", systemImage: "arrow.clockwise") { onReimport(playlist) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(playlist) }
                }
            }
        }
        .libraryPage(title: "Playlists")
        .toolbar {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                }
            }
        }
    }

    private var sources: [PlaylistSource] {
        PlaylistSource.allCases.filter { candidate in playlists.contains { $0.sourceProvider == candidate } }
    }

    private var shown: [Playlist] {
        let filtered = source.map { wanted in playlists.filter { $0.sourceProvider == wanted } } ?? playlists
        switch sort {
        case .recent:
            return filtered.sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func subtitle(for playlist: Playlist) -> String {
        // `itemCount`, not `items.count`: items are linked to their playlist by id, so the
        // relationship is not filled in.
        let count = playlist.itemCount
        return [playlist.sourceProvider?.libraryName, count == 1 ? "1 song" : "\(count) songs"]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var sourceFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: source == nil) { source = nil }
                ForEach(sources, id: \.self) { candidate in
                    chip(candidate.libraryName, selected: source == candidate) { source = candidate }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.cisumBg : .primary)
                .background(selected ? Color.primary : Color.cisumSurface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Songs

struct LibrarySongsView: View {
    enum Sort: String, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case recent = "Recently Added"
    }

    let songs: [LibraryIndex.Song]

    @State private var query = ""
    @State private var sort = Sort.title

    var body: some View {
        LibrarySongList(songs: shown, showsArtwork: true)
            .libraryPage(title: "Songs")
            .searchable(text: $query, prompt: "Search your songs")
            .toolbar {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
            }
    }

    private var shown: [LibraryIndex.Song] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let filtered = needle.isEmpty ? songs : songs.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.artist.localizedCaseInsensitiveContains(needle)
                || ($0.album?.localizedCaseInsensitiveContains(needle) ?? false)
        }
        switch sort {
        case .title:
            return filtered
        case .artist:
            return filtered.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .recent:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        }
    }
}

// MARK: - Albums

struct LibraryAlbumsView: View {
    let albums: [LibraryIndex.Album]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink {
                        LibraryAlbumView(album: album)
                    } label: {
                        LibraryTile(url: album.artworkURL, symbol: "square.stack", title: album.title, subtitle: album.artist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .libraryPage(title: "Albums")
    }
}

struct LibraryAlbumView: View {
    let album: LibraryIndex.Album

    var body: some View {
        LibrarySongList(songs: album.songs, showsArtwork: false) {
            VStack(spacing: 6) {
                LibraryArtwork(url: album.artworkURL, symbol: "square.stack", cornerRadius: 12)
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .padding(.bottom, 8)
                Text(album.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(Color.cisumYellow)
            }
            .frame(maxWidth: .infinity)
        }
        .libraryPage(title: "")
    }
}

// MARK: - Artists

struct LibraryArtistsView: View {
    let artists: [LibraryIndex.Artist]

    var body: some View {
        List(artists) { artist in
            NavigationLink {
                LibraryArtistView(artist: artist)
            } label: {
                LibraryListRow(
                    artwork: LibraryArtwork(url: artist.artworkURL, symbol: "music.mic", cornerRadius: 28),
                    title: artist.name,
                    subtitle: artist.songs.count == 1 ? "1 song" : "\(artist.songs.count) songs"
                )
            }
            .libraryRow()
        }
        .libraryPage(title: "Artists")
    }
}

struct LibraryArtistView: View {
    let artist: LibraryIndex.Artist

    var body: some View {
        LibrarySongList(songs: artist.songs, showsArtwork: true) {
            if !artist.albums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Albums")
                        .font(.title3.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(artist.albums) { album in
                                NavigationLink {
                                    LibraryAlbumView(album: album)
                                } label: {
                                    LibraryTile(url: album.artworkURL, symbol: "square.stack", title: album.title, subtitle: nil)
                                        .frame(width: 140)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Songs")
                        .font(.title3.bold())
                        .padding(.top, 8)
                }
            }
        }
        .libraryPage(title: artist.name)
    }
}

// MARK: - Shared pieces

/// A list of songs with Play and Shuffle, where tapping a song plays the list from it.
struct LibrarySongList<Header: View>: View {
    let songs: [LibraryIndex.Song]
    let showsArtwork: Bool
    @ViewBuilder var header: Header

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs

    var body: some View {
        List {
            header
                .libraryRow()

            HStack(spacing: 12) {
                Button { play(from: 0, shuffled: false) } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                Button { play(from: 0, shuffled: true) } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.primary)
            .disabled(songs.isEmpty)
            .libraryRow()

            ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                Button { play(from: offset, shuffled: false) } label: {
                    LibraryListRow(
                        artwork: showsArtwork ? LibraryArtwork(url: song.artworkURL) : nil,
                        title: song.title,
                        subtitle: [song.artist, song.album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
                    )
                }
                .libraryRow()
            }
        }
    }

    /// Queues the songs that can play — a row whose import never found it on any service cannot —
    /// starting from the tapped one.
    private func play(from offset: Int, shuffled: Bool) {
        let refs = songs.compactMap { $0.item.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }
        let tapped = songs[offset].item.playableRef(preferring: preferredSourceIDs)
        let start = tapped.flatMap { refs.firstIndex(of: $0) } ?? 0
        playbackCommands?.setQueue(refs, startIndex: start, shuffled: shuffled)
    }
}

extension LibrarySongList where Header == EmptyView {
    init(songs: [LibraryIndex.Song], showsArtwork: Bool) {
        self.init(songs: songs, showsArtwork: showsArtwork) { EmptyView() }
    }
}

struct LibraryArtwork: View {
    let url: URL?
    var symbol = "music.note"
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.cisumSurface
            .overlay {
                if let url {
                    KFImage(url)
                        .placeholder { placeholder }
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}

/// A square cover with a title and subtitle under it.
struct LibraryTile: View {
    let url: URL?
    let symbol: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LibraryArtwork(url: url, symbol: symbol, cornerRadius: 10)
                .padding(.bottom, 4)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct LibraryListRow: View {
    let artwork: LibraryArtwork?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            if let artwork {
                artwork.frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private extension View {
    /// The Library's list rows sit on the app background, not the system's grouped cards.
    func libraryRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .buttonStyle(.plain)
    }

    func libraryPage(title: String) -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.cisumBg)
            .navigationTitle(title)
            #if os(iOS)
            // Clears the floating mini player.
            .contentMargins(.bottom, 140, for: .scrollContent)
            #endif
    }
}

extension PlaylistSource {
    var libraryName: String {
        switch self {
        case .youtube: "YouTube"
        case .youtubeMusic: "YouTube Music"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .tidal: "TIDAL"
        case .qobuz: "Qobuz"
        case .local: "Created"
        case .shared: "Shared"
        case .unknown: "Other"
        }
    }

    /// The importer that can fetch this playlist again, if any.
    var importProvider: ImportProvider? {
        switch self {
        case .spotify: .spotify
        case .youtube, .youtubeMusic: .youtube
        case .appleMusic: .appleMusic
        default: nil
        }
    }
}
