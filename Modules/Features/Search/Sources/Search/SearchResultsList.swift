import Aesthetics
import Artists
import Catalog
import Kingfisher
import Library
import Models
import Player
import Playlists
import SwiftData
import SwiftUI
import Tracks
import Utilities

// MARK: - Search Results

/// Search results as filter chips over compact sections: a top-result card, then Artists, Songs
/// and Playlists, each previewing a few items with a "›" header that opens the full list.
///
/// The old view stacked every result of every source in one long list; this shows a little of
/// each kind and lets the chips or headers open the rest.
struct SearchResultsList: View {
    let searchViewModel: any SearchViewModelInterface
    @Binding var showNonPlayableAlert: Bool
    @Binding var nonPlayableMessage: String
    let onRowSelection: (FederatedSearchItem) -> Void

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Query private var libraryItems: [PlaylistItem]
    @Environment(\.catalog) private var catalog
    @Environment(\.importDownloadManager) private var importDownloadManager
    @State private var filter = SearchFilter.all
    @State private var topInset: CGFloat = 0
    /// Built when the library changes, not per keystroke. Building it inside `libraryMatches` ran
    /// the whole-library grouping and text normalisation on every body pass: ~0.94 s of main
    /// thread over 20 s of typing a query (Time Profiler, Release, device).
    @State private var libraryIndex = LibraryIndex(items: [])

    var body: some View {
        // Chips above the results rather than in a safe-area inset: either scroll view touching
        // the top edge takes the navigation area as content inset, a tall empty band.
        VStack(spacing: 0) {
            filterChips
            results
        }
        // The tab root ignores the safe area, so the status bar's height is applied by hand. Read
        // once here, not in `body`: reading the window during an update is what froze the tabs.
        .padding(.top, topInset)
        .onAppear { topInset = AppConstants.safeAreaInsets.top }
        .onChange(of: searchViewModel.searchText) { _, _ in
            filter = .all
        }
        // ponytail: same key as LibraryView — a metadata edit shows on the next add or delete.
        .task(id: libraryItems.count) {
            libraryIndex = LibraryIndex(items: libraryItems)
        }
        .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                switch filter {
                case .all:
                    allResults
                case .library:
                    songRows(libraryMatches.map(SearchSong.library))
                case .artists:
                    VStack(spacing: 4) {
                        ForEach(artists) { item in
                            Button { onRowSelection(item) } label: { SearchArtistRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                case .songs:
                    songRows(songs.map(SearchSong.result))
                case .playlists:
                    // One column: a PlaylistCard's stacked cover and side padding make it wider
                    // than half a phone, so two per row overlap.
                    LazyVStack(spacing: 8) {
                        ForEach(playlists) { playlistCard($0) }
                    }
                    .frame(maxWidth: .infinity)
                }

                if filter == .all, songs.isEmpty, artists.isEmpty, playlists.isEmpty {
                    Label("Connect Spotify in Settings for richer results.", systemImage: "person.crop.circle.badge.plus")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .contentMargins(.bottom, 140, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Data

    /// Every song result, best first, from Spotify, Apple Music and YouTube.
    private var songs: [FederatedSearchItem] {
        searchViewModel.unifiedTopResults
    }

    /// The artists the query names, then the artists of the top songs; sources pad their artist
    /// lists with anyone popular, and those are left out. Spotify's first, then YouTube Music's,
    /// one per name.
    private var artists: [FederatedSearchItem] {
        let query = tokenSet(from: searchViewModel.searchText)
        let topSongArtists = songs.prefix(3).map { normalizedRankingText($0.displayArtist) }
        var seen = Set<String>()
        let relevant = (searchViewModel.spotifyArtistResults + searchViewModel.youtubeArtistResults).filter { artist in
            let name = normalizedRankingText(artist.title)
            guard !name.isEmpty, seen.insert(name).inserted else { return false }
            return isNamed(artist, in: query) || topSongArtists.contains { $0.contains(name) }
        }
        return relevant.filter { isNamed($0, in: query) } + relevant.filter { !isNamed($0, in: query) }
    }

    /// Every word of the artist's name is in the query ("anti-hero taylor swift"), or the query is
    /// the start of their name ("kendrick").
    private func isNamed(_ artist: FederatedSearchItem, in query: Set<String>) -> Bool {
        let name = tokenSet(from: artist.title)
        return share(of: name, foundIn: query) == 1 || share(of: query, foundIn: name) == 1
    }

    /// YouTube Music's first: those open as a `PlaylistCard` with their tracks and no import.
    /// Spotify's only fill in when YouTube has none, so the shelf never mixes cards and tiles.
    private var playlists: [FederatedSearchItem] {
        searchViewModel.youtubePlaylistResults.isEmpty ? searchViewModel.spotifyPlaylistResults : searchViewModel.youtubePlaylistResults
    }

    /// The artist the query names, if one does — it heads the results with their songs.
    private var topArtist: FederatedSearchItem? {
        artists.first.flatMap { isNamed($0, in: tokenSet(from: searchViewModel.searchText)) ? $0 : nil }
    }

    private func songs(by artist: FederatedSearchItem) -> [FederatedSearchItem] {
        let name = normalizedRankingText(artist.title)
        return songs.filter { normalizedRankingText($0.displayArtist).contains(name) }
    }

    /// The user's own songs matching the query.
    private var libraryMatches: [LibraryIndex.Song] {
        let query = searchViewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return libraryIndex.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || ($0.album?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var availableFilters: [SearchFilter] {
        SearchFilter.allCases.filter { candidate in
            switch candidate {
            case .all: true
            case .library: !libraryMatches.isEmpty
            case .artists: !artists.isEmpty
            case .songs: !songs.isEmpty
            case .playlists: !playlists.isEmpty
            }
        }
    }

    // MARK: All Results

    @ViewBuilder
    private var allResults: some View {
        let artist = topArtist
        let cardSongs = Array((artist.map(songs(by:)) ?? songs).prefix(4))

        if let artist {
            topArtistCard(artist, songs: cardSongs)
        }

        if !artists.isEmpty {
            section("Artists", filter: .artists) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 26) {
                        ForEach(artists) { item in
                            Button { onRowSelection(item) } label: { artistBubble(item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }

        let previewSongs = Array(songs.filter { song in !(artist != nil && cardSongs.contains { $0.id == song.id }) }.prefix(4))
        if !previewSongs.isEmpty {
            section("Songs", filter: .songs) {
                songRows(previewSongs.map(SearchSong.result))
            }
        }

        if !libraryMatches.isEmpty {
            section("In Your Library", filter: .library) {
                songRows(Array(libraryMatches.prefix(4)).map(SearchSong.library))
            }
        }

        if !playlists.isEmpty {
            section("Playlists", filter: .playlists) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 26) {
                        ForEach(playlists) { playlistCard($0) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func topArtistCard(_ artist: FederatedSearchItem, songs: [FederatedSearchItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            Button { onRowSelection(artist) } label: {
                TopArtistSearchResultCard(
                    artistName: artist.title,
                    artistImageURL: artist.artworkURL,
                    previewArtworkURLs: songs.map(\.artworkURL)
                )
            }
            .buttonStyle(.plain)
            #else
            Button { onRowSelection(artist) } label: {
                HStack(spacing: 10) {
                    SearchArtwork(url: artist.artworkURL, cornerRadius: 22)
                        .frame(width: 44, height: 44)
                    Text(artist.title)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #endif

            if !songs.isEmpty {
                songRows(songs.map(SearchSong.result))
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, filter target: SearchFilter, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { filter = target }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            content()
        }
    }

    private var filterChips: some View {
        Picker("Filter", selection: $filter.animation(.snappy)) {
            ForEach(availableFilters, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func songRows(_ rows: [SearchSong]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                SearchSongRow(song: row.track) {
                    play(row, in: rows)
                }
            }
        }
    }

    private func play(_ row: SearchSong, in rows: [SearchSong]) {
        switch row {
        case let .result(item):
            onRowSelection(item)
        case .library:
            // Library songs play as a queue, like the Library's own song lists.
            let items = rows.compactMap { if case let .library(song) = $0 { song.item } else { nil } }
            let refs = items.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
            guard case let .library(song) = row,
                  let tapped = song.item.playableRef(preferring: preferredSourceIDs)
            else { return }
            playbackCommands?.setQueue(refs, startIndex: refs.firstIndex(of: tapped) ?? 0, shuffled: false)
        }
    }

    private func artistBubble(_ item: FederatedSearchItem) -> some View {
        VStack(spacing: 7) {
            SearchArtwork(url: item.artworkURL, cornerRadius: 50)
                .frame(width: 100, height: 100)
            Text(item.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .frame(width: 100)
        }
    }

    /// Every result playlist is the Playlists module's own card, opening with its tracks and
    /// importing nothing: YouTube Music's tracks come from the Catalog, Spotify's from the
    /// Spotify importer's track fetch.
    @ViewBuilder
    private func playlistCard(_ item: FederatedSearchItem) -> some View {
        switch item.payload {
        case let .youtubePlaylist(browseID):
            PlaylistCard(remote: RemotePlaylist(
                title: item.title, owner: item.subtitle, artworkURL: item.artworkURL,
                source: .youtubeMusic, sourceID: browseID,
                loadTracks: { [catalog] in
                    await (catalog?.playlistTracks(youtubeBrowseID: browseID) ?? []).map(\.incoming)
                },
                onAddToLibrary: { onRowSelection(item) }
            ))
        case let .spotifyPlaylist(playlist):
            PlaylistCard(remote: RemotePlaylist(
                title: playlist.name, owner: playlist.ownerName, artworkURL: playlist.artworkURL,
                source: .spotify, sourceID: playlist.id,
                loadTracks: { [importDownloadManager] in
                    let service = await importDownloadManager?.service(for: .spotify)
                    return (try? await service?.fetchTrackPage(playlistID: playlist.id, cursor: nil, offset: 0).tracks) ?? []
                },
                onAddToLibrary: { onRowSelection(item) }
            ))
        default:
            EmptyView()
        }
    }
}

/// The result chips, in the design's order. Kinds search has no results for yet (albums, music
/// videos, stations) are left out rather than shown empty.
enum SearchFilter: String, CaseIterable {
    case all = "All Results"
    case library = "Library"
    case artists = "Artists"
    case songs = "Songs"
    case playlists = "Playlists"
}

/// A song row's source: a search result, or one of the user's own Library songs.
enum SearchSong: Identifiable {
    case result(FederatedSearchItem)
    case library(LibraryIndex.Song)

    var id: String {
        switch self {
        case let .result(item): "result:\(item.id)"
        case let .library(song): "library:\(song.id)"
        }
    }

    var track: SavableTrack {
        switch self {
        case let .result(item):
            var youtubeID: String?, youtubeMusicID: String?, spotifyID: String?
            switch item.payload {
            case let .youtube(ref):
                if ref.isMusic { youtubeMusicID = ref.videoID } else { youtubeID = ref.videoID }
            case let .spotify(track):
                spotifyID = track.id
            default:
                break
            }
            return SavableTrack(
                title: item.title,
                artist: item.displayArtist,
                album: item.subtitle.split(separator: "•").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) },
                artworkURL: item.artworkURL,
                durationSeconds: item.durationSeconds,
                isExplicit: item.isExplicit,
                youtubeID: youtubeID,
                youtubeMusicID: youtubeMusicID,
                spotifyID: spotifyID
            )
        case let .library(song):
            return SavableTrack(
                title: song.title,
                artist: song.artist,
                album: song.album,
                artworkURL: song.artworkURL,
                durationSeconds: song.item.durationSeconds,
                youtubeID: song.item.youtubeID,
                youtubeMusicID: song.item.youtubeMusicID,
                spotifyID: song.item.spotifyID
            )
        }
    }
}

/// A song row: the Tracks module's `TrackListItem`, with Save and Add to Playlist in its context menu.
struct SearchSongRow: View {
    let song: SavableTrack
    let onPlay: () -> Void

    @Environment(\.savedLibrary) private var savedLibrary
    @State private var isSaved = false
    @State private var isAddingToPlaylist = false

    var body: some View {
        Button(action: onPlay) {
            TrackListItem(
                trackName: song.title,
                artistName: song.album.map { "\(song.artist) • \($0)" } ?? song.artist,
                duration: song.durationSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "",
                artworkURL: song.artworkURL,
                isExplicit: song.isExplicit
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isSaved ? "Remove from Saved" : "Save", systemImage: isSaved ? "star.slash" : "star") {
                Task { isSaved = await savedLibrary?.toggleSaved(song) ?? isSaved }
            }
            Button("Add to Playlist", systemImage: "text.badge.plus") { isAddingToPlaylist = true }
        }
        .task(id: song.fingerprint) {
            isSaved = await savedLibrary?.isSaved(fingerprint: song.fingerprint) ?? false
        }
        #if os(iOS)
        .sheet(isPresented: $isAddingToPlaylist) {
            AddToPlaylistSheet(track: song)
        }
        #endif
    }
}

/// Square (or, with a large radius, round) result artwork with a quiet placeholder.
struct SearchArtwork: View {
    let url: URL?
    let cornerRadius: CGFloat

    var body: some View {
        Color.fillSubtle
            .overlay {
                if let url {
                    KFImage(url)
                        .downsampling(size: CGSize(width: 320, height: 320))
                        .resizable()
                        .scaledToFill()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
