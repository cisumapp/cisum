#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import Player
import SwiftData
import SwiftUI
import Tracks
import YouTubeSDK

public struct AlbumCard: View {
    @State private var viewModel = AlbumViewModel()
    public let album: Album

    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(\.searchViewModel) private var searchViewModel
    @Environment(PlayerPresentationController.self) private var playerPresentationController

    @Query private var songs: [Song]

    public init(album: Album) {
        self.album = album
        let albumID = album.albumID
        _songs = Query(filter: #Predicate<Song> { $0.albumID == albumID })
    }

    public var body: some View {
        VStack {
            CardOpenTransition(backgroundColor: viewModel.backgroundColor) { isCardExpanded, _ in
                VStack {
                    AlbumCover(isCardExpanded: isCardExpanded, viewModel: viewModel, album: album)
                }
            } content: { _, _ in
                ZStack {
                    Color.clear
                        .frame(height: 1900)
                        .contentShape(.rect)

                    LazyVStack(alignment: .leading, spacing: 4) {
                        if songs.isEmpty {
                            Text("No tracks found")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(Array(songs.enumerated()), id: \.element.songID) { index, song in
                                Button {
                                    playTracks(startingAt: index)
                                } label: {
                                    TrackListItem(
                                        trackName: song.title,
                                        artistName: song.primaryArtistName ?? album.primaryArtistName ?? "",
                                        duration: formatDuration(song.durationSeconds),
                                        artworkURL: (song.artworkURLString ?? album.artworkURLString).flatMap { URL(string: $0) },
                                        isExplicit: song.isExplicit
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
            .frame(width: 175, height: 175)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical)
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func playTracks(startingAt index: Int) {
        guard !songs.isEmpty else { return }

        let externalTracks: [ExternalQueueTrack] = songs.compactMap { track in
            let sourceProvider = track.preferredFallbackProvider ?? .youtube
            let payload: FederatedSearchPayload
            let mediaID: String

            if sourceProvider == .spotify, let spotifyID = track.spotifyTrackID {
                mediaID = spotifyID
                let spotifyTrack = SpotifySearchTrack(
                    id: spotifyID,
                    title: track.title,
                    artistName: track.primaryArtistName ?? "",
                    albumName: track.albumTitle,
                    artworkURL: track.artworkURLString.flatMap { URL(string: $0) },
                    durationSeconds: track.durationSeconds ?? 0,
                    previewURL: track.spotifyPreviewURLString.flatMap { URL(string: $0) }
                )
                payload = .spotify(spotifyTrack)
            } else if let ytID = track.youtubeVideoID ?? track.youtubeMusicVideoID {
                mediaID = ytID
                let ytSong = YouTubeMusicSong(
                    id: ytID,
                    title: track.title,
                    artists: [track.primaryArtistName ?? ""].filter { !$0.isEmpty },
                    album: track.albumTitle,
                    duration: track.durationSeconds.map { TimeInterval($0) },
                    thumbnailURL: track.artworkURLString.flatMap { URL(string: $0) },
                    videoId: ytID,
                    isExplicit: track.isExplicit
                )
                payload = .youtubeMusic(ytSong)
            } else {
                return nil
            }

            let item = FederatedSearchItem(
                id: mediaID,
                title: track.title,
                subtitle: track.primaryArtistName ?? "",
                artworkURL: track.artworkURLString.flatMap { URL(string: $0) },
                durationSeconds: track.durationSeconds,
                isPlayable: true,
                isExplicit: track.isExplicit,
                audioQualityLabel: nil,
                audioCodecLabel: nil,
                payload: payload
            )

            return ExternalQueueTrack(
                mediaID: mediaID,
                title: track.title,
                artist: track.primaryArtistName ?? "",
                artworkURL: track.artworkURLString.flatMap { URL(string: $0) } ?? (album.artworkURLString.flatMap { URL(string: $0) }),
                service: sourceProvider == .spotify ? .spotify : .youtube,
                isExplicit: track.isExplicit,
                qualityLabelHint: nil,
                codecLabelHint: nil,
                resolvePayload: {
                    guard let resolved = try await searchViewModel?.resolveExternalStream(for: item) else {
                        throw NSError(domain: "AlbumCard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve stream"])
                    }
                    return resolved
                }
            )
        }

        playerViewModel.setQueue(externalTracks, startIndex: index)
        playerPresentationController.expand()
    }
}

#if DEBUG
#Preview {
    AlbumCard(album: Album(title: "Bad", normalizedTitle: "Bad"))
}
#endif

#endif
