import Aesthetics
import Kingfisher
import Library
import Models
import Playlists
import Plugins
import SwiftData
import SwiftUI
import Utilities

#if canImport(SpotifySDK)
import SpotifySDK

public struct SpotifyPlaylistImportSheet: View {
    private enum Theme {
        static let sheetBackground = Color.cisumBg
        static let surface = Color.cisumElevatedSurface
        static let mutedSurface = Color.cisumSurface
        static let primaryText = Color.cisumPrimaryText
        static let secondaryText = Color.cisumSecondaryText
        static let border = Color.cisumChromeBorder
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotifySessionCoordinator.self) private var coordinator
    private var centralStore: CentralMediaStore {
        CentralMediaStore(modelContainer: modelContext.container)
    }

    public let onImported: (String) -> Void

    public init(onImported: @escaping (String) -> Void) {
        self.onImported = onImported
    }

    @State private var playlistLink: String = ""
    @State private var isImportingLink: Bool = false
    @State private var isLoadingLibrary: Bool = false
    @State private var isImportingLikedSongs: Bool = false
    @State private var importingPlaylistID: String?
    @State private var personalPlaylists: [SpotifyPersonalPlaylistSummary] = []
    @State private var likedSongsSummary: SpotifyLibraryPlaylistSummary?
    @State private var errorMessage: String?

    @MainActor
    private func resolvedImportService() async -> SpotifyPlaylistImportService? {
        await coordinator.restoreSessionIfNeeded()

        let sdk = coordinator.sdk ?? coordinator.session.map { SpotifySDK(session: $0) }
        guard let sdk else { return nil }

        return SpotifyPlaylistImportService(
            sdk: sdk,
            playlistStore: PlaylistLibraryStore(modelContainer: modelContext.container),
            onSpotifyPlaylistImported: { [container = modelContext.container] playlist in
                let centralStore = CentralMediaStore(modelContainer: container)
                Task {
                    _ = await centralStore.upsertSpotifyPlaylist(playlist)
                }
            }
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                importSheetBackground

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroCard
                        importByLinkCard
                        personalLibraryCard
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    await refreshLibrary()
                }
            }
            .navigationTitle("Add Spotify Playlist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .alert("Import Failed", isPresented: showsErrorAlert) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task(id: coordinator.sessionRevision) {
            await refreshLibrary()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                if let profile = coordinator.accountProfile,
                   let avatarURL = profile.avatarImages.first?.url {
                    KFImage(avatarURL)
                        .placeholder {
                            Circle()
                                .fill(Theme.mutedSurface)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(
                                            Theme.secondaryText
                                        )
                                }
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.mutedSurface)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(Theme.secondaryText)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spotify import")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)

                    Text(coordinator.accountDescriptor)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)

                    Text(
                        coordinator.isAuthenticated
                            ? "Your playlists and liked songs load automatically when this sheet opens."
                            : "Connect Spotify in Settings to import your library."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(coordinator.sessionStatusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.mutedSurface, in: Capsule())
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                heroChip(
                    title: "\(personalPlaylists.count) playlists",
                    systemImage: "music.note.list"
                )
                heroChip(
                    title: likedSongsSummary?.trackCount.map { "\($0) liked" } ?? "Liked Songs",
                    systemImage: "heart.fill"
                )
                heroChip(
                    title: coordinator.isAuthenticated ? "Connected" : "Offline",
                    systemImage: coordinator.isAuthenticated
                        ? "checkmark.shield.fill" : "wifi.slash"
                )
            }

            if isLoadingLibrary {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.secondaryText)
                    Text("Loading your Spotify library…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await refreshLibrary() }
                    } label: {
                        Label(
                            personalPlaylists.isEmpty ? "Load library" : "Refresh library",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(Color(red: 0.0, green: 0.44, blue: 0.89), in: Capsule())
                    .disabled(isLoadingLibrary)

                    Button {
                        Task { await importLikedSongs() }
                    } label: {
                        Label("Import liked songs", systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.0, green: 0.44, blue: 0.89))
                    .background(
                        Color(red: 0.0, green: 0.44, blue: 0.89).opacity(0.10), in: Capsule()
                    )
                    .disabled(isImportingLikedSongs || !coordinator.isAuthenticated)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
        )
    }

    private var importByLinkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Import by link",
                subtitle: "Paste a playlist URL, spotify:playlist URI, or raw ID."
            )

            TextField(
                "https://open.spotify.com/playlist/…",
                text: $playlistLink,
                axis: .vertical
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .padding(14)
            .background(
                Theme.mutedSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(Theme.primaryText)

            Button {
                Task { await importFromLink() }
            } label: {
                HStack {
                    if isImportingLink {
                        ProgressView().controlSize(.small).tint(.primary)
                    } else {
                        Label("Import playlist", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(
                Color(red: 0.0, green: 0.44, blue: 0.89),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .disabled(
                isImportingLink
                    || playlistLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            Text(
                "Paste any Spotify playlist link, URI, or raw ID. cisum will create a fresh library entry for every import."
            )
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
        )
    }

    private var personalLibraryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Spotify library")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)

                    Text(
                        coordinator.isAuthenticated
                            ? "Tap a playlist to import it instantly."
                            : "Connect Spotify in Settings to load personal playlists and liked songs."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    Task { await refreshLibrary() }
                } label: {
                    Label(
                        isLoadingLibrary ? "Loading" : "Refresh", systemImage: "arrow.clockwise"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primaryText)
                .background(Theme.mutedSurface, in: Capsule())
                .disabled(isLoadingLibrary)
            }

            if !coordinator.isAuthenticated {
                EmptyStateCard(
                    title: "Spotify not connected",
                    subtitle:
                    "Open Settings and sign in with Spotify to load your personal library here.",
                    systemImage: "exclamationmark.circle"
                )
            } else if isLoadingLibrary, personalPlaylists.isEmpty, likedSongsSummary == nil {
                LoadingCard(message: "Loading your Spotify library…")
            } else {
                likedSongsCard

                if personalPlaylists.isEmpty {
                    EmptyStateCard(
                        title: "No playlists found",
                        subtitle:
                        "Your Spotify playlists will appear here after the library loads.",
                        systemImage: "tray"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(personalPlaylists) { playlist in
                            Button {
                                Task { await importPersonalPlaylist(playlist) }
                            } label: {
                                personalPlaylistCard(playlist)
                            }
                            .buttonStyle(.plain)
                            .disabled(importingPlaylistID == playlist.id)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
        )
    }

    private func personalPlaylistCard(_ playlist: SpotifyPersonalPlaylistSummary) -> some View {
        HStack(spacing: 12) {
            KFImage(playlist.artworkURL)
                .placeholder {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.mutedSurface)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let ownerName = playlist.ownerName, !ownerName.isEmpty {
                        Text(ownerName)
                    }

                    if let totalTracks = playlist.totalTracks {
                        Text("•")
                        Text("\(totalTracks) tracks")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if importingPlaylistID == playlist.id {
                ProgressView()
                    .tint(Theme.primaryText)
            } else {
                Label("Import", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.44, blue: 0.89))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
        )
        .contentShape(Rectangle())
    }

    private var likedSongsCard: some View {
        Button {
            Task { await importLikedSongs() }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.mutedSurface)
                    .frame(width: 64, height: 64)
                    .overlay {
                        if isImportingLikedSongs {
                            ProgressView()
                                .tint(Color(red: 1.0, green: 0.08, blue: 0.28))
                        } else {
                            Image(systemName: "heart.fill")
                                .font(.title3.weight(.black))
                                .foregroundStyle(Color(red: 1.0, green: 0.08, blue: 0.28))
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(likedSongsSummary?.name ?? "Liked Songs")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)

                    Text(likedSongsSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isImportingLikedSongs {
                    ProgressView()
                        .tint(Theme.primaryText)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.0, green: 0.44, blue: 0.89))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                Theme.border, lineWidth: 1
                            )
                    }
            )
        }
        .buttonStyle(.plain)
        .disabled(isImportingLikedSongs || !coordinator.isAuthenticated)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heroChip(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.mutedSurface, in: Capsule())
        .foregroundStyle(Theme.secondaryText)
    }

    private var importSheetBackground: some View {
        Theme.sheetBackground
            .ignoresSafeArea()
    }

    private struct EmptyStateCard: View {
        let title: String
        let subtitle: String
        let systemImage: String

        /*
         #if DEBUG
             @ObserveInjection var forceRedraw
         #endif
         */

        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 42, height: 42)
                    .background(
                        Theme.mutedSurface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                Theme.border, lineWidth: 1
                            )
                    }
            )
        }
    }

    private struct LoadingCard: View {
        let message: String

        /*
         #if DEBUG
             @ObserveInjection var forceRedraw
         #endif
         */

        var body: some View {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.secondaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                Theme.border, lineWidth: 1
                            )
                    }
            )
        }
    }

    private var showsErrorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

fileprivate extension SpotifyPlaylistImportSheet {
    @MainActor
    func importFromLink() async {
        let trimmed = playlistLink.trimmingCharacters(in: .whitespacesAndNewlines)
        Utilities.Logger.log("Importing Spotify playlist from link: \(trimmed)")
        guard !trimmed.isEmpty else {
            Utilities.Logger.log("Import link is empty, skipping.")
            return
        }
        guard let service = await resolvedImportService() else {
            Utilities.Logger.log("Spotify SDK unavailable for link import.")
            errorMessage = SpotifyImportError.sdkUnavailable.errorDescription
            return
        }

        isImportingLink = true
        defer { isImportingLink = false }

        do {
            let playlistID = try await service.importPlaylist(fromLink: trimmed)
            Utilities.Logger.log("Successfully imported Spotify playlist.")
            onImported(playlistID)
            dismiss()
        } catch {
            Utilities.Logger.log("Failed to import playlist from link: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func refreshLibrary() async {
        Utilities.Logger.log("Refreshing Spotify library...")
        errorMessage = nil
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        await coordinator.restoreSessionIfNeeded()

        guard coordinator.isAuthenticated else {
            Utilities.Logger.log("Spotify not authenticated, clearing personal playlists.")
            personalPlaylists = []
            likedSongsSummary = nil
            return
        }

        guard let service = await resolvedImportService() else {
            Utilities.Logger.log("Spotify SDK unavailable for library refresh.")
            errorMessage = SpotifyImportError.sdkUnavailable.errorDescription
            return
        }

        do {
            Utilities.Logger.log("Fetching personal playlists...")
            personalPlaylists = try await service.fetchPersonalPlaylists(limit: .max)
            Utilities.Logger.log("Fetched \(personalPlaylists.count) personal playlists.")
        } catch {
            Utilities.Logger.log("Failed to fetch personal playlists: \(error.localizedDescription)")
            personalPlaylists = []
            errorMessage = error.localizedDescription
        }

        do {
            Utilities.Logger.log("Fetching liked songs summary...")
            likedSongsSummary = try await service.fetchLikedSongsSummary()
            Utilities.Logger.log(
                "Fetched liked songs summary: \(likedSongsSummary?.trackCount ?? 0) tracks."
            )
        } catch {
            Utilities.Logger.log("Failed to fetch liked songs summary: \(error.localizedDescription)")
            likedSongsSummary = nil
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func importPersonalPlaylist(_ playlist: SpotifyPersonalPlaylistSummary) async {
        Utilities.Logger.log("Importing personal playlist: \(playlist.name) (\(playlist.id))")
        guard let service = await resolvedImportService() else {
            Utilities.Logger.log("Spotify SDK unavailable for personal playlist import.")
            errorMessage = SpotifyImportError.sdkUnavailable.errorDescription
            return
        }

        importingPlaylistID = playlist.id
        defer { importingPlaylistID = nil }

        do {
            let playlistID = try await service.importPlaylist(
                id: playlist.id, nameOverride: playlist.name
            )
            Utilities.Logger.log("Successfully imported Spotify playlist.")
            onImported(playlistID)
            dismiss()
        } catch {
            Utilities.Logger.log("Failed to import personal playlist: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func importLikedSongs() async {
        Utilities.Logger.log("Importing Spotify liked songs...")
        guard let service = await resolvedImportService() else {
            Utilities.Logger.log("Spotify SDK unavailable for liked songs import.")
            errorMessage = SpotifyImportError.sdkUnavailable.errorDescription
            return
        }

        isImportingLikedSongs = true
        defer { isImportingLikedSongs = false }

        do {
            let playlistID = try await service.importLikedSongs()
            Utilities.Logger.log(
                "Successfully imported liked songs into playlist"
            )
            onImported(playlistID)
            dismiss()
        } catch {
            Utilities.Logger.log("Failed to import liked songs: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    var likedSongsSubtitle: String {
        if let likedSongsSummary {
            if let count = likedSongsSummary.trackCount {
                return "\(count) songs from your Spotify likes."
            }

            return likedSongsSummary.ownerDisplayName ?? likedSongsSummary.ownerUsername
                ?? "Import your liked tracks into a local playlist."
        }

        return "Import your liked tracks into a local playlist."
    }
}

#endif
