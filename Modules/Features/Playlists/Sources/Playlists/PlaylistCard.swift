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

public struct PlaylistCard: View, Equatable {
    @State private var viewModel = PlaylistViewModel()
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    public let playlist: Models.Playlist

    @State var showAllImages: Bool = true

    public init(playlist: Models.Playlist, showAllImages: Bool = true) {
        self.playlist = playlist
        self.showAllImages = showAllImages
    }

    public nonisolated static func == (lhs: PlaylistCard, rhs: PlaylistCard) -> Bool {
        lhs.playlist.playlistID == rhs.playlist.playlistID &&
            lhs.playlist.updatedAt == rhs.playlist.updatedAt
    }

    public var body: some View {
        VStack {
            CardOpenTransition(backgroundColor: viewModel.backgroundColor) { isCardExpanded, _ in
                VStack {
                    PlaylistCover(isCardExpanded: isCardExpanded, viewModel: viewModel, playlist: playlist, showAllImages: $showAllImages)
                }
            } content: { _, _ in
                PlaylistTrackListView(playlist: playlist)
            }
            .frame(width: 175, height: 175)

            Spacer()
        }
        .padding(.horizontal, 24)
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
                        .foregroundStyle(.secondary)
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

        if let tidalID = validID(track.tidalID) {
            mediaID = tidalID
            let rep = TrackRepresentation(providerID: "tidal", providerTrackID: tidalID, title: track.title, artist: artistName, duration: duration, isrc: track.isrc, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: tidalID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "tidal", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "tidal", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "tidal", value: artistName), name: artistName)),
                isrc: track.isrc.flatMap { try? ISRC($0) },
                duration: duration ?? 0,
                representations: [rep]
            )
            payload = .providerSDKTrack(sdkTrack)
        } else if let qobuzID = validID(track.qobuzID) {
            mediaID = qobuzID
            let rep = TrackRepresentation(providerID: "qobuz", providerTrackID: qobuzID, title: track.title, artist: artistName, duration: duration, isrc: track.isrc, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: qobuzID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "qobuz", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "qobuz", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "qobuz", value: artistName), name: artistName)),
                isrc: track.isrc.flatMap { try? ISRC($0) },
                duration: duration ?? 0,
                representations: [rep]
            )
            payload = .providerSDKTrack(sdkTrack)
        } else if let appleID = validID(track.appleMusicID) {
            mediaID = appleID
            let rep = TrackRepresentation(providerID: "appleMusic", providerTrackID: appleID, title: track.title, artist: artistName, duration: duration, isrc: track.isrc, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: appleID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "appleMusic", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "appleMusic", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "appleMusic", value: artistName), name: artistName)),
                isrc: track.isrc.flatMap { try? ISRC($0) },
                duration: duration ?? 0,
                representations: [rep]
            )
            payload = .providerSDKTrack(sdkTrack)
        } else if let ytMusicID = validID(track.youtubeMusicID) {
            mediaID = ytMusicID
            let ytSong = YouTubeMusicSong(id: ytMusicID, title: track.title, artists: [artistName].filter { !$0.isEmpty }, album: track.albumName, duration: duration.map { TimeInterval($0) }, thumbnailURL: artworkURL, videoId: ytMusicID, isExplicit: false)
            payload = .youtubeMusic(ytSong)
        } else if let ytID = validID(track.youtubeID) {
            mediaID = ytID
            let ytVideo = makeSyntheticYouTubeVideo(videoID: ytID, title: track.title, author: artistName, durationSeconds: duration, artworkURL: artworkURL)
            payload = .youtubeVideo(ytVideo)
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
            let youtubeVideo = makeSyntheticYouTubeVideo(videoID: youtubeID, title: track.title, author: artistName, durationSeconds: duration, artworkURL: artworkURL)
            payload = .youtubeVideo(youtubeVideo)
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

    private func makeSyntheticYouTubeVideo(
        videoID: String,
        title: String,
        author: String,
        durationSeconds: Double?,
        artworkURL: URL?
    ) -> YouTubeVideo {
        let lengthStr = durationSeconds.map { String(Int($0)) } ?? "0"
        return YouTubeVideo(
            id: videoID,
            title: title,
            author: author,
            lengthInSeconds: lengthStr,
            thumbnailURL: artworkURL?.absoluteString
        )
    }
}

#Preview {
    PlaylistCard(playlist: Models.Playlist(title: "tera sharmana", normalizedTitle: "tera sharmana"))
}

#endif
