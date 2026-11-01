import Aesthetics
import Authentication
import Kingfisher
import Models
import Playlists
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
    @Environment(\.importDownloadManager) private var importDownloadManager
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]

    @State private var viewModel = LibraryViewModel()
    #if os(iOS)
    /// Only `NavigationBarView` reads this; the macOS chrome ignores scroll position.
    @State private var scrollOffset: CGFloat = 0
    #endif
    @State private var isPresentingNewPlaylist = false
    @State private var newPlaylistName = ""

    // Precomputed sorted arrays to avoid O(n log n) on every render
    @State private var sortedShelfPlaylists: [Playlist] = []
    @State private var sortedRecentPlaylists: [Playlist] = []
    @State private var sortedSharedPlaylists: [Playlist] = []
    @State private var cachedPinnedPlaylist: Playlist?
    @State private var isSharedExpanded = true

    public var body: some View {
        #if os(iOS)
        NavigationBarView(
            title: "Library",
            scrollOffset: $scrollOffset,
            customActions: [
                ProfileMenuCustomAction(title: "New Playlist") {
                    isPresentingNewPlaylist = true
                },
                ProfileMenuCustomAction(title: "Import Playlist") {
                    viewModel.isPresentingImportPicker = true
                },
            ]
        ) {
            content
        }
        #else
        // `NavigationBarView` is built on UIKit's blur + scroll-driven title, neither of
        // which exists on AppKit, so there is no nav bar here to supply the `ScrollView`.
        // Without one, the sections overflow the window and the shell clips them.
        ScrollView {
            content
                .contentMargins(.top, 8)
        }
        #endif
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

            if !sortedSharedPlaylists.isEmpty {
                sectionDivider

                LibraryRecentlyAddedSectionView(
                    isExpanded: $isSharedExpanded,
                    title: "Shared",
                    recentlyAddedPlaylists: sortedSharedPlaylists,
                    isCompactShelfMode: viewModel.isCompactShelfMode,
                    onNavigate: { envRouter.navigate(to: .playlist(id: $0.playlistID)) },
                    onDelete: deleteImportedPlaylist,
                    fallbackSymbolProvider: fallbackSymbol,
                    fallbackGradientProvider: fallbackGradient,
                    songsLabelProvider: songsLabel
                )
            }
        }
        #if os(iOS)
        // Clears the floating mini player, which sits over the content on iOS. The macOS
        // transport lives in the band above the content, so nothing floats here.
        .safeAreaPadding(.bottom, 140)
        #endif
        // Unified import sheet (service picker → multi-select → background import).
        .sheet(isPresented: $viewModel.isPresentingImportPicker) {
            ImportServiceSheet()
        }
        .alert("New Playlist", isPresented: $isPresentingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") { createLocalPlaylist() }
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
        // Link-imported "Shared" playlists get their own section, out of the generic shelves.
        let nonShared = playlists.filter { $0.sourceProvider != .shared }

        // Shelf playlists - mode-dependent sort
        sortedShelfPlaylists = switch viewModel.shelfSortMode {
        case .alphabetical:
            nonShared.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent:
            nonShared.sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }
        }

        // Recently added - always by date
        sortedRecentPlaylists = nonShared.sorted {
            ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt)
        }

        // Shared (received via cisum links) - by date
        sortedSharedPlaylists = playlists
            .filter { $0.sourceProvider == .shared }
            .sorted { ($0.importedAt ?? $0.createdAt) > ($1.importedAt ?? $1.createdAt) }

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

    /// Imports (or refreshes) Spotify Liked Songs through the shared import pipeline, then opens it.
    private func openLikedSongs() async {
        #if canImport(SpotifySDK)
        guard let importDownloadManager else { return }
        viewModel.isSyncingLikedSongs = true
        defer { viewModel.isSyncingLikedSongs = false }

        let likedSongs = ImportablePlaylistRef(
            id: SpotifyImportService.likedSongsPlaylistID,
            title: "Liked Songs",
            subtitle: nil,
            ownerName: nil,
            artworkURL: nil,
            trackCount: nil
        )
        guard let playlistID = await importDownloadManager.importAndWait(provider: .spotify, playlistRef: likedSongs) else {
            viewModel.libraryActionErrorMessage = "Couldn't import your Spotify Liked Songs. Check that Spotify is connected."
            return
        }
        envRouter.navigate(to: .playlist(id: playlistID))
        #endif
    }

    private var libraryActionErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.libraryActionErrorMessage != nil },
            set: {
                if !$0 {
                    viewModel.libraryActionErrorMessage = nil
                }
            }
        )
    }

    private func createLocalPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, let playlistLibraryStore else { return }
        Task {
            let id = await playlistLibraryStore.createLocalPlaylist(title: name)
            envRouter.navigate(to: .playlist(id: id))
        }
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
        case .local:
            "music.note.list"
        case .shared:
            "square.and.arrow.down"
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
    var title: String = "Recently Added"
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
                title: title,
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
