#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import Player
import ProviderSDK
import SwiftData
import SwiftUI
import Tracks
import YouTubeSDK

public struct PlaylistCard: View {
    @State private var viewModel = PlaylistViewModel()
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    public let playlist: Models.Playlist

    @State var showAllImages: Bool = true

    public init(playlist: Models.Playlist, showAllImages: Bool = true) {
        self.playlist = playlist
        self.showAllImages = showAllImages
    }

    public var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let scale = ResponsiveLayout.DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)
        
        VStack {
            CardOpenTransition(backgroundColor: viewModel.backgroundColor) { isCardExpanded, _ in
                VStack {
                    PlaylistCover(isCardExpanded: isCardExpanded, viewModel: viewModel, playlist: playlist, showAllImages: $showAllImages)
                }
            } content: { _, _ in
                PlaylistTrackListView(playlist: playlist)
            }
            .frame(width: 175 * scale, height: 175 * scale)
            .legibilityBackground(viewModel.backgroundColor)

            Spacer()
        }
        .padding(.horizontal, 24 * scale)
        .padding(.vertical)
    }
}

private struct PlaylistTrackListView: View {
    let playlist: Models.Playlist

    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.searchViewModel) private var searchViewModel
    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore

    @Query private var tracks: [PlaylistItem]

    init(playlist: Models.Playlist) {
        self.playlist = playlist
        let playlistID = playlist.playlistID
        _tracks = Query(
            filter: #Predicate<PlaylistItem> { $0.playlistID == playlistID },
            sort: \.sortIndex
        )
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: 1900)
                .contentShape(.rect)
                
            LazyVStack(alignment: .leading, spacing: 4) {
                if tracks.isEmpty {
                    Text("No tracks found")
                        .legibleForeground(.secondary)
                        .padding()
                } else {
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
                        
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
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

        let queueTracks = tracks.compactMap { makePlayableQueueTrack(for: $0) }
        guard !queueTracks.isEmpty else { return }

        let selectedItem = tracks[index]
        let selectedMediaID = playbackMediaID(for: selectedItem)
        guard let startIndex = queueTracks.firstIndex(where: { $0.mediaID == selectedMediaID })
        else { return }

        playerViewModel.setQueue(queueTracks, startIndex: startIndex)
        playerPresentationController.expand()
    }

    private func makePlayableQueueTrack(for track: PlaylistItem) -> ExternalQueueTrack {
        let artworkURL = track.artworkURLString.flatMap { URL(string: $0) }
        let searchItem = makeSearchItem(for: track, artworkURL: artworkURL)
        let itemKey = track.itemKey

        return ExternalQueueTrack(
            mediaID: playbackMediaID(for: track),
            title: track.title,
            artist: track.artistName ?? "",
            artworkURL: artworkURL,
            service: searchItem.service,
            isExplicit: false,
            qualityLabelHint: nil,
            codecLabelHint: nil,
            resolvePayload: {
                guard let resolved = try await searchViewModel?.resolveExternalStream(for: searchItem) else {
                    throw FederatedSearchError.noPlayableStream(
                        "Unable to resolve a playable stream for \"\(track.title)\"."
                    )
                }

                // Cache the resolved ID!
                if resolved.mediaID != searchItem.id {
                    await playlistLibraryStore?.updateProviderID(for: itemKey, provider: resolved.service.rawValue, trackID: resolved.mediaID)
                }

                return resolved
            }
        )
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

#endif
