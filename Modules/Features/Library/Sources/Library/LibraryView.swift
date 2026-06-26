import Aesthetics
import Kingfisher
import Models
import Playlists
import Plugins
import SwiftData
import SwiftUI
import Utilities
import YouTubeSDK

#if canImport(SpotifySDK)
import SpotifySDK
#endif

public struct LibraryView: View {
    public init() {}

    @Environment(SpotifySessionCoordinator.self) private var spotifyCoordinator
    @Environment(\.router) private var envRouter
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    @Environment(\.centralMediaStore) private var centralMediaStore
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    enum ImportProvider: String, CaseIterable, Identifiable {
        case youtube = "YouTube"
        case spotify = "Spotify"
        var id: String {
            rawValue
        }
    }

    @State private var viewModel = LibraryViewModel()
    @State private var scrollOffset: CGFloat = 0

    // Precomputed sorted arrays to avoid O(n log n) on every render
    @State private var sortedShelfPlaylists: [Playlist] = []
    @State private var sortedRecentPlaylists: [Playlist] = []
    @State private var cachedPinnedPlaylist: Playlist?

    public var body: some View {
        NavigationBarView(
            title: "Library",
            scrollOffset: $scrollOffset,
            customActions: [
                ProfileMenuCustomAction(title: "Import Playlist") {
                    viewModel.isPresentingImportPicker = true
                },
            ]
        ) {
            content
        }
    }

    var content: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            LibraryPinsSectionView(
                isExpanded: $viewModel.isPinsExpanded,
                pinnedPlaylist: cachedPinnedPlaylist,
                onNavigate: { envRouter.navigate(to: .playlist(id: $0.playlistID)) },
                onDelete: deleteImportedPlaylist,
                fallbackSymbolProvider: fallbackSymbol,
                fallbackGradientProvider: fallbackGradient
            )

            sectionDivider

            LibraryPlaylistsShelfSectionView(
                isExpanded: $viewModel.isPlaylistsExpanded,
                shelfPlaylists: sortedShelfPlaylists,
                isCompactShelfMode: viewModel.isCompactShelfMode,
                isAuthenticated: spotifyCoordinator.isAuthenticated,
                isSyncingLikedSongs: viewModel.isSyncingLikedSongs,
                likedSongsTitle: viewModel.spotifySnapshot.likedSongsSummary?.name ?? viewModel.spotifySnapshot.likedSongsTitle,
                likedSongsCount: viewModel.spotifySnapshot.likedSongsCount,
                onOpenLikedSongs: { Task { await openLikedSongs() } },
                onNavigate: { envRouter.navigate(to: .playlist(id: $0.playlistID)) },
                onDelete: deleteImportedPlaylist,
                fallbackSymbolProvider: fallbackSymbol,
                fallbackGradientProvider: fallbackGradient,
                songsLabelProvider: songsLabel
            )

            sectionDivider

            LibraryRecentlyAddedSectionView(
                isExpanded: $viewModel.isRecentlyAddedExpanded,
                recentlyAddedPlaylists: sortedRecentPlaylists,
                isCompactShelfMode: viewModel.isCompactShelfMode,
                onNavigate: { envRouter.navigate(to: .playlist(id: $0.playlistID)) },
                onDelete: deleteImportedPlaylist,
                fallbackSymbolProvider: fallbackSymbol,
                fallbackGradientProvider: fallbackGradient,
                songsLabelProvider: songsLabel
            )
        }
        .safeAreaPadding(.bottom, 140)
        // YouTube import sheet
        .sheet(isPresented: $viewModel.isPresentingYouTubeImport) {
            YouTubePlaylistImportSheet { importedPlaylistID in
                envRouter.navigate(to: .playlist(id: importedPlaylistID))
            }
        }
        // Spotify import sheet
        #if canImport(SpotifySDK)
        .sheet(isPresented: $viewModel.isPresentingSpotifyImport) {
            SpotifyPlaylistImportSheet { importedPlaylistID in
                envRouter.navigate(to: .playlist(id: importedPlaylistID))
            }
            .environment(spotifyCoordinator)
        }
        #endif
        // Unified import sheet (service picker → multi-select → background import).
        .sheet(isPresented: $viewModel.isPresentingImportPicker) {
            ImportServiceSheet()
        }
        .alert("Library Action Failed", isPresented: libraryActionErrorBinding) {
            Button("OK", role: .cancel) {
                viewModel.libraryActionErrorMessage = nil
            }
        } message: {
            Text(viewModel.libraryActionErrorMessage ?? "Unknown error")
        }
        .task(id: spotifyCoordinator.sessionRevision) {
            await refreshSpotifySnapshot()
        }
        .onChange(of: playlists.count) { _, _ in
            updateSortedPlaylists()
        }
        .onChange(of: viewModel.shelfSortMode) { _, _ in
            updateSortedPlaylists()
        }
        .onAppear {
            updateSortedPlaylists()
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 14) {
            Button {
                envRouter.pop()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)
                    .padding(11)
                    .background(
                        Circle()
                            .fill(Color.cisumSurface.opacity(0.92))
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                            }
                    )
            }
            .buttonStyle(.plain)

            Text("Library")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                headerControlButton(icon: "arrow.up.arrow.down") {
                    viewModel.toggleShelfSortMode()
                }

                headerControlButton(icon: "line.3.horizontal.decrease") {
                    viewModel.isCompactShelfMode.toggle()
                }

                headerControlButton(icon: "plus") {
                    viewModel.isPresentingImportPicker = true
                }

                headerControlButton(icon: "magnifyingglass") {
                    envRouter.navigate(to: .search)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.cisumSurface.opacity(0.92))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    }
            )
        }
    }

    private func updateSortedPlaylists() {
        // Shelf playlists - mode-dependent sort
        sortedShelfPlaylists = switch viewModel.shelfSortMode {
        case .alphabetical:
            playlists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent:
            playlists.sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }
        }

        // Recently added - always by date
        sortedRecentPlaylists = playlists.sorted {
            ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt)
        }

        // Pinned - most recently played/imported
        cachedPinnedPlaylist = playlists.max {
            let lhsDate = $0.lastPlayedAt ?? $0.importedAt ?? $0.createdAt
            let rhsDate = $1.lastPlayedAt ?? $1.importedAt ?? $1.createdAt
            return lhsDate < rhsDate
        }
    }

    private var shelfCardSize: CGFloat {
        viewModel.isCompactShelfMode ? 148 : 160
    }

    private var shelfCardSpacing: CGFloat {
        viewModel.isCompactShelfMode ? 12 : 16
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.vertical, 2)
            .padding(.horizontal)
    }

    private func librarySectionHeader(
        title: String,
        showsChevronAfterTitle: Bool,
        isExpanded: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)

                if showsChevronAfterTitle {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.38))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.cisumSurface.opacity(0.92))
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                            }
                    )
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -180))
            }
            .buttonStyle(.plain)
        }
    }

    private func headerControlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }

    private func songsLabel(for count: Int) -> String {
        count == 1 ? "1 Song" : "\(count) Songs"
    }

    private func deleteImportedPlaylist(_ playlist: Playlist) {
        let playlistID = playlist.playlistID
        Task {
            await playlistLibraryStore?.deletePlaylist(playlistID: playlistID)
        }
    }

    private func openLikedSongs() async {
        #if canImport(SpotifySDK)
        guard let service = spotifyImportService else {
            viewModel.libraryActionErrorMessage = SpotifyImportError.sdkUnavailable.errorDescription
            return
        }

        viewModel.isSyncingLikedSongs = true
        defer { viewModel.isSyncingLikedSongs = false }

        do {
            let playlistID = try await service.importLikedSongs()
            envRouter.navigate(to: .playlist(id: playlistID))
        } catch {
            viewModel.libraryActionErrorMessage = error.localizedDescription
        }
        #endif
    }

    private var spotifyImportService: SpotifyPlaylistImportService? {
        #if canImport(SpotifySDK)
        guard let sdk = spotifyCoordinator.sdk,
              let playlistLibraryStore,
              let centralMediaStore
        else { return nil }
        return SpotifyPlaylistImportService(
            sdk: sdk,
            playlistStore: playlistLibraryStore,
            onSpotifyPlaylistImported: { playlist in
                Task {
                    _ = await centralMediaStore.upsertSpotifyPlaylist(playlist)
                }
            }
        )
        #else
        return nil
        #endif
    }

    private var libraryActionErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.libraryActionErrorMessage != nil },
            set: { if !$0 { viewModel.libraryActionErrorMessage = nil } }
        )
    }

    private func fallbackSymbol(for sourceProvider: PlaylistSource) -> String {
        switch sourceProvider {
        case .spotify:
            "music.note.list"
        case .youtube, .youtubeMusic:
            "play.rectangle.fill"
        case .appleMusic:
            "music.note"
        case .tidal, .qobuz:
            "music.quarternote.3"
        case .unknown:
            "tray.full"
        }
    }

    private func fallbackGradient(for playlist: Playlist) -> LinearGradient {
        let title = playlist.title.lowercased()

        if title.contains("chill") {
            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.81, blue: 0.56),
                    Color(red: 0.42, green: 0.49, blue: 0.74),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if title.contains("favorite") {
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.92, blue: 0.84),
                    Color(red: 0.90, green: 0.94, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if title.contains("meteo") || title.contains("linkin") {
            return LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.17, blue: 0.14),
                    Color(red: 0.08, green: 0.07, blue: 0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let palettes: [LinearGradient] = [
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.84, blue: 0.67),
                    Color(red: 0.44, green: 0.52, blue: 0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.88, blue: 0.93),
                    Color(red: 0.44, green: 0.50, blue: 0.68),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.24, blue: 0.26),
                    Color(red: 0.62, green: 0.61, blue: 0.58),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            LinearGradient(
                colors: [
                    Color(red: 0.89, green: 0.78, blue: 0.62),
                    Color(red: 0.34, green: 0.42, blue: 0.60),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
        ]

        let seed = title.unicodeScalars.reduce(into: 0) { result, scalar in
            result = (result &* 31) &+ Int(scalar.value)
        }

        return palettes[abs(seed) % palettes.count]
    }

    private func refreshSpotifySnapshot() async {
        #if canImport(SpotifySDK)
        guard spotifyCoordinator.isAuthenticated,
              let sdk = spotifyCoordinator.sdk
        else {
            viewModel.spotifySnapshot = .empty
            return
        }

        viewModel.isLoadingSpotifySnapshot = true
        defer { viewModel.isLoadingSpotifySnapshot = false }

        do {
            PerfLog.info("LibraryView: Fetching Spotify snapshot...")
            async let playlists = sdk.account.playlists(limit: 40)
            async let likedSongsPage = sdk.account.likedSongs(limit: 1)
            let (playlistsResult, likedSongs) = try await (playlists, likedSongsPage)

            let count = likedSongs.totalCount ?? likedSongs.items.count
            PerfLog.info(
                "LibraryView: Spotify snapshot fetched. Playlists: \(playlistsResult.count), Liked Songs: \(count)"
            )

            viewModel.spotifySnapshot = SpotifyLibrarySnapshot(
                accountDisplayName: spotifyCoordinator.accountProfile?.displayName ?? "Spotify",
                username: spotifyCoordinator.accountProfile?.username,
                playlistCount: playlistsResult.count,
                likedSongsCount: count,
                likedSongsTitle: "Liked Songs",
                likedSongsSummary: nil,
                totalCount: playlistsResult.count,
                featuredPlaylists: Array(playlistsResult.prefix(6))
            )
        } catch {
            PerfLog.info(
                "LibraryView: Failed to fetch Spotify snapshot: \(error.localizedDescription)"
            )
            viewModel.spotifySnapshot = .empty
        }
        #else
        viewModel.spotifySnapshot = .empty
        #endif
    }
}

private struct LibraryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cisumSurface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        )
    }
}

private struct SpotifyShelfCard: View {
    let playlist: SpotifyLibraryPlaylistSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(playlist.ownerDisplayName ?? playlist.ownerUsername ?? "Spotify")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(trackCountLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.cisumSurface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = playlist.artworkURL {
            KFImage(artworkURL)
                .placeholder {
                    fallbackArtwork
                }
                .resizable()
                .scaledToFill()
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            fallbackArtwork
                .frame(height: 132)
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.green.opacity(0.9), Color.black.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
    }

    private var trackCountLabel: String {
        if let trackCount = playlist.trackCount {
            return "\(trackCount) tracks"
        }

        return "Spotify playlist"
    }
}

private struct EmptyStateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(
                    Color.cisumElevatedSurface.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.cisumSurface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        )
    }
}

private struct LoadingShelfCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.primary)
            Text("Loading your Spotify library…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.cisumSurface.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }
        )
    }
}

private struct LibraryTileData {
    let title: String
    let secondaryText: String?
    let artworkURL: URL?
    let fallbackSymbol: String
    let fallbackGradient: LinearGradient
}

#if canImport(SpotifySDK)
public struct SpotifyLibrarySnapshot: Sendable {
    var accountDisplayName: String
    var username: String?
    var playlistCount: Int
    var likedSongsCount: Int
    var likedSongsTitle: String
    var likedSongsSummary: SpotifyLibraryPlaylistSummary?
    var totalCount: Int?
    var featuredPlaylists: [SpotifyLibraryPlaylistSummary]

    static let empty = SpotifyLibrarySnapshot(
        accountDisplayName: "Spotify",
        username: nil,
        playlistCount: 0,
        likedSongsCount: 0,
        likedSongsTitle: "Liked Songs",
        likedSongsSummary: nil,
        totalCount: nil,
        featuredPlaylists: []
    )

    var playlistCountLabel: String {
        "\(playlistCount)"
    }

    var likedSongsCountLabel: String {
        "\(likedSongsCount)"
    }
}
#endif

private struct LibrarySectionHeaderView: View {
    let title: String
    let showsChevronAfterTitle: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)

                if showsChevronAfterTitle {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.38))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.cisumSurface.opacity(0.92))
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                            }
                    )
                    .rotationEffect(.degrees(isExpanded ? 0 : -180))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ImportedPlaylistButtonView: View {
    let playlist: Playlist
    let size: CGFloat
    let detailText: String?
    let fallbackSymbol: String
    let fallbackGradient: LinearGradient
    let onNavigate: (Playlist) -> Void
    let onDelete: (Playlist) -> Void

    var body: some View {
        PlaylistCard(playlist: playlist)
            .contextMenu {
                Button(role: .destructive) {
                    onDelete(playlist)
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
    }
}

private struct LibraryPinsSectionView: View {
    @Binding var isExpanded: Bool
    let pinnedPlaylist: Playlist?
    let onNavigate: (Playlist) -> Void
    let onDelete: (Playlist) -> Void
    let fallbackSymbolProvider: (PlaylistSource) -> String
    let fallbackGradientProvider: (Playlist) -> LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeaderView(
                title: "Pins",
                showsChevronAfterTitle: false,
                isExpanded: $isExpanded
            )

            if isExpanded {
                if let pinnedPlaylist {
                    ImportedPlaylistButtonView(
                        playlist: pinnedPlaylist,
                        size: 160,
                        detailText: nil,
                        fallbackSymbol: fallbackSymbolProvider(pinnedPlaylist.sourceProvider ?? .unknown),
                        fallbackGradient: fallbackGradientProvider(pinnedPlaylist),
                        onNavigate: onNavigate,
                        onDelete: onDelete
                    )
                } else {
                    EmptyStateCard(
                        title: "No pins yet",
                        subtitle: "Import a playlist to surface it here.",
                        systemImage: "pin"
                    )
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct LibraryPlaylistsShelfSectionView: View {
    @Binding var isExpanded: Bool
    let shelfPlaylists: [Playlist]
    let isCompactShelfMode: Bool
    let isAuthenticated: Bool
    let isSyncingLikedSongs: Bool
    let likedSongsTitle: String
    let likedSongsCount: Int
    let onOpenLikedSongs: () -> Void
    let onNavigate: (Playlist) -> Void
    let onDelete: (Playlist) -> Void
    let fallbackSymbolProvider: (PlaylistSource) -> String
    let fallbackGradientProvider: (Playlist) -> LinearGradient
    let songsLabelProvider: (Int) -> String

    var body: some View {
        let shelfCardSize: CGFloat = isCompactShelfMode ? 148 : 160
        let shelfCardSpacing: CGFloat = isCompactShelfMode ? 12 : 16

        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeaderView(
                title: "Playlists",
                showsChevronAfterTitle: true,
                isExpanded: $isExpanded
            )

            if isExpanded {
                if shelfPlaylists.isEmpty {
                    EmptyStateCard(
                        title: "No playlists yet",
                        subtitle: "Import from Spotify or YouTube to build this shelf.",
                        systemImage: "music.note.list"
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: shelfCardSpacing) {
                            if isAuthenticated {
                                PlaylistCard(
                                    playlist: Playlist(
                                        playlistID: "likedSongs",
                                        title: likedSongsTitle,
                                        normalizedTitle: likedSongsTitle.lowercased(),
                                        artworkURLString: "bundle://liked",
                                        sourceProvider: .spotify,
                                        itemCount: likedSongsCount
                                    )
                                )
                            }

                            ForEach(shelfPlaylists) { playlist in
                                ImportedPlaylistButtonView(
                                    playlist: playlist,
                                    size: shelfCardSize,
                                    detailText: songsLabelProvider(playlist.itemCount),
                                    fallbackSymbol: fallbackSymbolProvider(playlist.sourceProvider ?? .unknown),
                                    fallbackGradient: fallbackGradientProvider(playlist),
                                    onNavigate: onNavigate,
                                    onDelete: onDelete
                                )
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

private struct LibraryRecentlyAddedSectionView: View {
    @Binding var isExpanded: Bool
    let recentlyAddedPlaylists: [Playlist]
    let isCompactShelfMode: Bool
    let onNavigate: (Playlist) -> Void
    let onDelete: (Playlist) -> Void
    let fallbackSymbolProvider: (PlaylistSource) -> String
    let fallbackGradientProvider: (Playlist) -> LinearGradient
    let songsLabelProvider: (Int) -> String

    var body: some View {
        let shelfCardSize: CGFloat = isCompactShelfMode ? 148 : 160
        let shelfCardSpacing: CGFloat = isCompactShelfMode ? 12 : 16

        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeaderView(
                title: "Recently Added",
                showsChevronAfterTitle: true,
                isExpanded: $isExpanded
            )

            if isExpanded {
                if recentlyAddedPlaylists.isEmpty {
                    EmptyStateCard(
                        title: "Nothing imported yet",
                        subtitle: "Your newest playlists will appear here once you add them.",
                        systemImage: "clock.arrow.circlepath"
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: shelfCardSpacing) {
                            ForEach(recentlyAddedPlaylists) { playlist in
                                ImportedPlaylistButtonView(
                                    playlist: playlist,
                                    size: shelfCardSize,
                                    detailText: playlist.subtitle?.uppercased() ?? songsLabelProvider(playlist.itemCount),
                                    fallbackSymbol: fallbackSymbolProvider(playlist.sourceProvider ?? .unknown),
                                    fallbackGradient: fallbackGradientProvider(playlist),
                                    onNavigate: onNavigate,
                                    onDelete: onDelete
                                )
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    LibraryView()
}
