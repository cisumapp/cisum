import Aesthetics
import Kingfisher
import Models
import Player
import ProviderSDK
import SwiftData
import SwiftUI
import Tracks
import Utilities
import YouTubeSDK

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct PlaylistCard: View {
    @State private var viewModel = PlaylistViewModel()
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    public let playlist: Models.Playlist
    /// Set for a playlist that is not in the library: its tracks load when the card opens.
    let remote: RemotePlaylist?

    @State var showAllImages: Bool = true

    public init(playlist: Models.Playlist, showAllImages: Bool = true) {
        self.playlist = playlist
        self.remote = nil
        self.showAllImages = showAllImages
    }

    /// A playlist that is not in the library, from any provider. It looks and opens like a
    /// saved one; its tracks are loaded the first time it opens, and nothing is saved unless the
    /// user picks Add to Library.
    public init(remote: RemotePlaylist) {
        // Unsaved: SwiftData models work as plain values until they are inserted.
        self.playlist = Models.Playlist(
            playlistID: "remote:\(remote.source.rawValue):\(remote.sourceID)",
            title: remote.title,
            normalizedTitle: remote.title.lowercased(),
            ownerName: remote.owner,
            artworkURLString: remote.artworkURL?.absoluteString,
            sourceProvider: remote.source,
            sourcePlaylistID: remote.sourceID
        )
        self.remote = remote
        self.showAllImages = true
    }

    public var body: some View {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #elseif os(macOS)
        let screenWidth = NSScreen.main?.frame.width ?? 0
        #endif
        let scale = ResponsiveLayout.scaleFactor(forScreenWidth: screenWidth)

        VStack {
            CardOpenTransition(backgroundColor: viewModel.backgroundColor) { isCardExpanded, _ in
                VStack {
                    PlaylistCover(isCardExpanded: isCardExpanded, viewModel: viewModel, playlist: playlist, showAllImages: $showAllImages)
                }
            } content: { _, _ in
                PlaylistTrackListView(playlist: playlist, remote: remote)
            }
            .frame(width: 175 * scale, height: 175 * scale)
            .legibilityBackground(viewModel.backgroundColor)

            Spacer()
        }
        .padding(.horizontal, 24 * scale)
        .padding(.vertical)
    }
}

/// A playlist that is not in the library, and where its tracks come from.
public struct RemotePlaylist {
    public let title: String
    public let owner: String?
    public let artworkURL: URL?
    public let source: PlaylistSource
    public let sourceID: String
    /// Fetches the tracks; called the first time the card opens.
    public let loadTracks: @MainActor () async -> [IncomingTrack]
    /// Imports it; `nil` leaves Add to Library out of the menu.
    public let onAddToLibrary: (@MainActor () async -> Void)?

    public init(
        title: String,
        owner: String?,
        artworkURL: URL?,
        source: PlaylistSource,
        sourceID: String,
        loadTracks: @escaping @MainActor () async -> [IncomingTrack],
        onAddToLibrary: (@MainActor () async -> Void)? = nil
    ) {
        self.title = title
        self.owner = owner
        self.artworkURL = artworkURL
        self.source = source
        self.sourceID = sourceID
        self.loadTracks = loadTracks
        self.onAddToLibrary = onAddToLibrary
    }
}

struct PlaylistTrackListView: View {
    let playlist: Models.Playlist
    var remote: RemotePlaylist?
    /// When true, renders as a full-screen scrolling detail (cover + tracks) instead of the card's
    /// expanded fullScreenCover content.
    var isDetail: Bool = false

    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.modelContext) private var modelContext
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    @Environment(\.savedLibrary) private var savedLibrary
    @Environment(\.router) private var router

    @State private var trackToAdd: SavableTrack?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var shareURL: IdentifiableURL?
    @State private var coverViewModel = PlaylistViewModel()

    @Query private var savedTracks: [PlaylistItem]
    @State private var remoteTracks: [PlaylistItem]?

    /// The saved tracks, or for a remote playlist the ones fetched when it opened.
    private var tracks: [PlaylistItem] {
        remote == nil ? savedTracks : remoteTracks ?? []
    }

    init(playlist: Models.Playlist, remote: RemotePlaylist? = nil, isDetail: Bool = false) {
        self.playlist = playlist
        self.remote = remote
        self.isDetail = isDetail
        let playlistID = playlist.playlistID
        _savedTracks = Query(
            filter: #Predicate<PlaylistItem> { $0.playlistID == playlistID },
            sort: \.sortIndex
        )
    }

    var body: some View {
        Group {
            if isDetail {
                GeometryReader { geo in
                    PaletteScrollView(palette: coverViewModel.palette, heroHeight: geo.size.width) {
                        PlaylistCover(isCardExpanded: true, viewModel: coverViewModel, playlist: playlist, showAllImages: .constant(false))
                    } content: {
                        trackList
                            .padding()
                    }
                }
                // A playlist with no artwork of its own ("Saved", most local ones) takes its
                // colours from its first track, so the cover and the page share one palette.
                .task(id: tracks.first?.artworkURLString) {
                    guard playlist.artworkURLString == nil,
                          let artwork = tracks.first?.artworkURLString,
                          let url = URL(string: artwork)
                    else { return }
                    await coverViewModel.fetchPaletteIfNeeded(from: ImageColorExtractor.paletteURL(from: url))
                }
            } else {
                ZStack {
                    Color.clear
                        .frame(height: 1900)
                        .contentShape(.rect)

                    trackList
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding()
                }
            }
        }
        .task {
            guard let remote, remoteTracks == nil else { return }
            let id = playlist.playlistID
            let loaded = await remote.loadTracks().enumerated().map { index, track in
                PlaylistItem(remote: track, playlistID: id, sortIndex: index)
            }
            // Crossfades the skeleton into the rows rather than swapping them.
            withAnimation(.easeOut(duration: 0.3)) { remoteTracks = loaded }
        }
        #if os(iOS)
        // `AddToPlaylistSheet` and `ShareSheet` are UIKit presentations that do not exist on
        // macOS yet. The buttons that would present them are gated to match, so macOS never
        // offers a menu item that goes nowhere.
        .sheet(item: $trackToAdd) { track in
            AddToPlaylistSheet(track: track)
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(url: item.url)
        }
        #endif
        .alert("Rename Playlist", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let id = playlist.playlistID
                Task { await playlistLibraryStore?.renamePlaylist(playlistID: id, title: name) }
            }
        }
    }

    private var trackList: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if remote != nil, remoteTracks == nil {
                TrackListSkeleton(count: 8)
                    .transition(.opacity)
            } else if tracks.isEmpty {
                Text("No tracks found")
                    .legibleForeground(.secondary)
                    .padding()
            } else {
                playlistHeader
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                ForEach(tracks, id: \.itemKey) { track in
                    Button {
                        Task {
                            let index = tracks.firstIndex(where: { $0.itemKey == track.itemKey }) ?? 0
                            await playPlaylist(startingAt: index)
                        }
                    } label: {
                        TrackListItem(
                            trackName: track.title,
                            artistName: track.artistName ?? "",
                            duration: formatDuration(track.durationSeconds),
                            artworkURL: track.artworkURLString.flatMap { URL(string: $0) }
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { _ = await savedLibrary?.toggleSaved(savableTrack(for: track)) }
                        } label: {
                            Label("Save", systemImage: "star")
                        }

                        #if os(iOS)
                        Button {
                            trackToAdd = savableTrack(for: track)
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                        #endif

                        if let sharedSong = SharedSong(savable: savableTrack(for: track)),
                           let shareURL = CisumLink.song(sharedSong).webURL()
                        {
                            ShareLink(item: shareURL) {
                                Label("Share Song", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    Divider()
                        .padding(.horizontal)
                }
            }
        }
    }

    /// The shareable representation of the whole playlist: `.imported` for provider-sourced
    /// playlists, `.embedded` (tracklist) for local/Saved/Shared playlists. Turned into a short
    /// Universal Link by `PlaylistShareLink` at share time.
    private var sharedPlaylistValue: SharedPlaylist? {
        if let source = playlist.sourceProvider,
           let provider = mediaProvider(from: source),
           let sourceID = playlist.sourcePlaylistID
        {
            return .imported(provider: provider, sourceID: sourceID, name: playlist.title)
        }
        let songs = tracks.compactMap(sharedSong(for:))
        guard !songs.isEmpty else { return nil }
        return .embedded(name: playlist.title, author: playlist.ownerName, sharedBy: nil, tracks: songs)
    }

    private func mediaProvider(from source: PlaylistSource) -> MediaProvider? {
        switch source {
        case .spotify: .spotify
        case .youtube: .youtube
        case .youtubeMusic: .youtubeMusic
        case .appleMusic: .appleMusic
        case .tidal: .tidal
        case .qobuz: .qobuz
        case .local, .shared, .unknown: nil
        }
    }

    private func sharedSong(for item: PlaylistItem) -> SharedSong? {
        let provider: MediaProvider
        let id: String
        if let ytMusic = item.youtubeMusicID {
            provider = .youtubeMusic; id = ytMusic
        } else if let yt = item.youtubeID {
            provider = .youtube; id = yt
        } else if let spotify = item.spotifyID {
            provider = .spotify; id = spotify
        } else {
            return nil
        }
        return SharedSong(
            provider: provider,
            id: id,
            title: item.title,
            artist: item.artistName ?? "",
            album: item.albumName,
            artworkURL: item.artworkURLString.flatMap { URL(string: $0) },
            durationSeconds: item.durationSeconds
        )
    }

    private func savableTrack(for track: PlaylistItem) -> SavableTrack {
        SavableTrack(
            title: track.title,
            artist: track.artistName ?? "",
            album: track.albumName,
            artworkURL: track.artworkURLString.flatMap { URL(string: $0) },
            durationSeconds: track.durationSeconds,
            sourceTrackID: track.sourceTrackID,
            youtubeID: track.youtubeID,
            youtubeMusicID: track.youtubeMusicID,
            spotifyID: track.spotifyID
        )
    }

    private var playlistHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
                    .font(.subheadline.weight(.medium))
                    .legibleForeground(.secondary)

                Spacer()

                moreMenu
            }

            HStack(spacing: 12) {
                Button {
                    Task { await playPlaylist(startingAt: 0) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .cardGlassButtonStyle()

                Button {
                    Task { await playShuffled() }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .cardGlassButtonStyle()
            }
            .legibleForeground(.primary)
        }
    }

    private var moreMenu: some View {
        Menu {
            #if os(iOS)
            if let shared = sharedPlaylistValue {
                Button {
                    Task {
                        if let url = await PlaylistShareLink.makeShareURL(for: shared) {
                            shareURL = IdentifiableURL(url: url)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            #endif

            if let onAdd = remote?.onAddToLibrary {
                Button {
                    Task { await onAdd() }
                } label: {
                    Label("Add to Library", systemImage: "plus")
                }
            }

            // Opt-in merge: prepend the cisum "Saved" collection on top of an imported playlist.
            if remote == nil, playlist.sourceProvider != .local {
                Button {
                    let id = playlist.playlistID
                    Task { await playlistLibraryStore?.mergeSaved(into: id) }
                } label: {
                    Label("Merge Saved into this", systemImage: "square.stack.3d.down.forward")
                }
            }

            // Organize actions for user-made local playlists.
            if playlist.sourceProvider == .local {
                Button {
                    renameText = playlist.title
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    let id = playlist.playlistID
                    Task {
                        await playlistLibraryStore?.deletePlaylist(playlistID: id)
                        router.pop()
                    }
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .legibleForeground(.secondary)
        }
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func playPlaylist(startingAt index: Int) async {
        guard tracks.indices.contains(index) else { return }

        // Items with no resolved provider id are dropped, so the tapped row's position has to be
        // recomputed against the filtered list rather than reused.
        let refs = tracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }

        let selected = tracks[index].playableRef(preferring: preferredSourceIDs)
        let startIndex = selected.flatMap { refs.firstIndex(of: $0) } ?? 0

        playbackCommands?.setQueue(refs, startIndex: startIndex, shuffled: false)
        markPlayed()
        playerPresentationController.expand()
    }

    private func playShuffled() async {
        let refs = tracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }

        // The queue shuffles itself; shuffling here as well would defeat restoring the original
        // order when the user turns shuffle back off.
        playbackCommands?.setQueue(refs, startIndex: 0, shuffled: true)
        markPlayed()
        playerPresentationController.expand()
    }

    private func markPlayed() {
        guard remote == nil else { return }
        let id = playlist.playlistID
        Task { await playlistLibraryStore?.markPlaylistPlayed(playlistID: id) }
    }

    private func playbackMediaID(for track: PlaylistItem) -> String {
        let validID = { (id: String?) -> String? in
            guard let unwrapped = id?.trimmingCharacters(in: .whitespacesAndNewlines), !unwrapped.isEmpty else { return nil }
            return unwrapped
        }
        return validID(track.tidalID) ??
            validID(track.qobuzID) ??
            validID(track.appleMusicID) ??
            validID(track.youtubeMusicID) ??
            validID(track.youtubeID) ??
            validID(track.spotifyID) ??
            validID(track.soundcloudID) ??
            validID(track.deezerID) ??
            track.itemKey
    }

    private func makeSearchItem(for track: PlaylistItem, artworkURL: URL?) -> FederatedSearchItem {
        let artistName = track.artistName ?? ""
        let duration = track.durationSeconds

        let validID = { (id: String?) -> String? in
            guard let unwrapped = id?.trimmingCharacters(in: .whitespacesAndNewlines), !unwrapped.isEmpty else { return nil }
            return unwrapped
        }

        let payload: FederatedSearchPayload
        let mediaID: String

        func providerPayload(_ providerID: String, _ id: String) -> FederatedSearchPayload {
            let rep = MediaRepresentation(providerID: providerID, providerTrackID: id, title: track.title, artist: artistName, durationSeconds: duration, isrc: track.isrc, artworkURL: artworkURL)
            return .providerSDK(ProviderMediaRef(canonicalID: id, title: track.title, artist: artistName, album: track.albumName, artworkURL: artworkURL, durationSeconds: duration, representations: [rep]))
        }

        if let tidalID = validID(track.tidalID) {
            mediaID = tidalID
            payload = providerPayload("tidal", tidalID)
        } else if let qobuzID = validID(track.qobuzID) {
            mediaID = qobuzID
            payload = providerPayload("qobuz", qobuzID)
        } else if let appleID = validID(track.appleMusicID) {
            mediaID = appleID
            payload = providerPayload("appleMusic", appleID)
        } else if let ytMusicID = validID(track.youtubeMusicID) {
            mediaID = ytMusicID
            payload = .youtube(YouTubeMediaRef(videoID: ytMusicID, title: track.title, artist: artistName, album: track.albumName, artworkURL: artworkURL, durationSeconds: duration, isExplicit: false, isMusic: true))
        } else if let ytID = validID(track.youtubeID) {
            mediaID = ytID
            payload = .youtube(YouTubeMediaRef(videoID: ytID, title: track.title, artist: artistName, artworkURL: artworkURL, durationSeconds: duration, isExplicit: false, isMusic: false))
        } else if let spotifyID = validID(track.spotifyID) {
            mediaID = spotifyID
            let spotifyTrack = SpotifySearchTrack(id: spotifyID, title: track.title, artistName: artistName, albumName: track.albumName, artworkURL: artworkURL, durationSeconds: duration ?? 0, previewURL: nil, isrc: track.isrc)
            payload = .spotify(spotifyTrack)
        } else if playlist.sourceProvider == .spotify {
            let spotifyID = track.sourceTrackID ?? track.itemKey
            mediaID = spotifyID
            let spotifyTrack = SpotifySearchTrack(id: spotifyID, title: track.title, artistName: artistName, albumName: track.albumName, artworkURL: artworkURL, durationSeconds: duration ?? 0, previewURL: nil, isrc: track.isrc)
            payload = .spotify(spotifyTrack)
        } else {
            let youtubeID = track.sourceTrackID ?? track.itemKey
            mediaID = youtubeID
            payload = .youtube(YouTubeMediaRef(videoID: youtubeID, title: track.title, artist: artistName, artworkURL: artworkURL, durationSeconds: duration, isExplicit: false, isMusic: false))
        }

        return FederatedSearchItem(
            id: mediaID,
            title: track.title,
            subtitle: artistName.isEmpty ? (track.albumName ?? "YouTube") : artistName,
            artworkURL: artworkURL,
            durationSeconds: duration,
            isPlayable: true,
            isExplicit: false,
            audioQualityLabel: nil,
            audioCodecLabel: nil,
            payload: payload
        )
    }
}

#Preview {
    PlaylistCard(playlist: Models.Playlist(title: "tera sharmana", normalizedTitle: "tera sharmana"))
}
