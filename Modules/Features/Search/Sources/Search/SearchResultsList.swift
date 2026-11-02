import Aesthetics
import Kingfisher
import Models
import Player
import SwiftData
import SwiftUI
import Utilities

// MARK: - Search Results

/// Search results as filter chips over compact sections: a top-result card, then Artists, Songs
/// and Playlists, each previewing a few items with a "›" header that opens the full list.
///
/// The old view stacked every result of every source in one long list; this shows a little of
/// each kind and lets the chips or headers open the rest.
struct SearchResultsList: View {
    let searchViewModel: any SearchViewModelInterface
    @Binding var isImportingSpotifyPlaylistID: String?
    @Binding var showNonPlayableAlert: Bool
    @Binding var nonPlayableMessage: String
    let onRowSelection: (FederatedSearchItem) -> Void

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Query private var libraryItems: [PlaylistItem]
    @State private var filter = SearchFilter.all

    var body: some View {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                        ForEach(playlists) { playlistTile($0) }
                    }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            filterChips
        }
        .contentMargins(.bottom, 140, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: searchViewModel.searchText) { _, _ in
            filter = .all
        }
        .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Data

    /// Every song result, best first: the unified ranking, then Spotify's own list for anything it
    /// missed.
    private var songs: [FederatedSearchItem] {
        var seen = Set<String>()
        return (searchViewModel.unifiedTopResults + searchViewModel.spotifyTrackResults)
            .filter { seen.insert($0.id).inserted }
    }

    private var artists: [FederatedSearchItem] {
        searchViewModel.spotifyArtistResults
    }

    private var playlists: [FederatedSearchItem] {
        searchViewModel.spotifyPlaylistResults
    }

    /// The artist the query names, if one does — it heads the results with their songs.
    private var topArtist: FederatedSearchItem? {
        let query = normalizedRankingText(searchViewModel.searchText)
        guard !query.isEmpty, let first = artists.first else { return nil }
        let name = normalizedRankingText(first.title)
        return name.contains(query) || query.contains(name) ? first : nil
    }

    private func songs(by artist: FederatedSearchItem) -> [FederatedSearchItem] {
        let name = normalizedRankingText(artist.title)
        return songs.filter { normalizedRankingText($0.displayArtist).contains(name) }
    }

    /// The user's own songs matching the query.
    private var libraryMatches: [LibraryIndex.Song] {
        let query = searchViewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return LibraryIndex(items: libraryItems).songs.filter {
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
                        ForEach(playlists) { playlistTile($0).frame(width: 160) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func topArtistCard(_ artist: FederatedSearchItem, songs: [FederatedSearchItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if !songs.isEmpty {
                songRows(songs.map(SearchSong.result))
            }
        }
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(availableFilters, id: \.self) { candidate in
                    Button {
                        withAnimation(.snappy) { filter = candidate }
                    } label: {
                        Text(candidate.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background {
                                if filter == candidate {
                                    Capsule().fill(.fill.tertiary)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func songRows(_ rows: [SearchSong]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                if offset > 0 {
                    Rectangle()
                        .fill(.primary.opacity(0.1))
                        .frame(height: 0.5)
                        .padding(.vertical, 5)
                }
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
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
                .frame(width: 100)
        }
    }

    private func playlistTile(_ item: FederatedSearchItem) -> some View {
        let isImporting = { if case let .spotifyPlaylist(playlist) = item.payload { playlist.id == isImportingSpotifyPlaylistID } else { false } }()
        return Button { onRowSelection(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                SearchArtwork(url: item.artworkURL, cornerRadius: 10)
                    .overlay {
                        if isImporting {
                            ProgressView()
                        }
                    }
                    .padding(.bottom, 3)
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
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

/// A compact song row: artwork, title, album or artist, then Save and a menu.
struct SearchSongRow: View {
    let song: SavableTrack
    let onPlay: () -> Void

    @Environment(\.savedLibrary) private var savedLibrary
    @State private var isSaved = false
    @State private var isAddingToPlaylist = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    SearchArtwork(url: song.artworkURL, cornerRadius: 6)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.8))
                        Text(song.album ?? song.artist)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 20) {
                Button {
                    Task { isSaved = await savedLibrary?.toggleSaved(song) ?? isSaved }
                } label: {
                    Image(systemName: isSaved ? "star.fill" : "star")
                }
                .accessibilityLabel(isSaved ? "Remove from Saved" : "Save")

                Menu {
                    Button("Add to Playlist", systemImage: "text.badge.plus") { isAddingToPlaylist = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.trailing, 4)
        }
        .padding(4)
        .frame(height: 42)
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
        Color.primary.opacity(0.08)
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
