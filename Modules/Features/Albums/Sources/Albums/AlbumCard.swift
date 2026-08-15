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

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController

    @Query private var songs: [Song]

    public init(album: Album) {
        self.album = album
        let albumID = album.albumID
        _songs = Query(filter: #Predicate<Song> { $0.albumID == albumID })
    }

    public var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let scale = ResponsiveLayout.DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)

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
            .frame(width: 175 * scale, height: 175 * scale)

            Spacer()
        }
        .padding(.horizontal, 24 * scale)
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

        // Each song already knows which services it exists on, so playing an album is a mapping
        // rather than a reconstruction. This replaced a 66-line block that rebuilt a
        // SpotifySearchTrack, a FederatedSearchItem, a payload enum, and a closure calling back
        // into the search view model — per track, on every tap.
        let refs = songs.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }

        playbackCommands?.setQueue(refs, startIndex: index, shuffled: false)
        playerPresentationController.expand()
    }
}

#if DEBUG
#Preview {
    AlbumCard(album: Album(title: "Bad", normalizedTitle: "Bad"))
}
#endif

#endif
