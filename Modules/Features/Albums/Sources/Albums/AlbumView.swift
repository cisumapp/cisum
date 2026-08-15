#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import Player
import SwiftData
import SwiftUI
import YouTubeSDK

public struct AlbumView: View {
    let album: Album
    @State private var viewModel = AlbumViewModel()
    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController

    @Query private var tracks: [Song]

    public init(album: Album) {
        self.album = album
        let albumID = album.albumID
        _tracks = Query(filter: #Predicate<Song> { $0.albumID == albumID })
    }

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    AlbumCover(isCardExpanded: true, viewModel: viewModel, album: album)
                        .frame(width: geo.size.width, height: geo.size.width)

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Button {
                                playTracks(startingAt: 0)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 50)
                                        .fill(viewModel.backgroundColor)

                                    Text("Play")
                                        .foregroundStyle(viewModel.titleColor.safeTextColor(over: viewModel.backgroundColor))
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(width: 160, height: 48)
                            .buttonStyle(.plain)

                            Button {
                                playTracks(startingAt: tracks.isEmpty ? 0 : Int.random(in: 0 ..< tracks.count), shuffled: true)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.backgroundColor)

                                    Image(systemName: "shuffle")
                                        .foregroundStyle(viewModel.titleColor.safeTextColor(over: viewModel.backgroundColor))
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 24)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.songID) { index, track in
                                AlbumTrackRow(index: index, track: track) {
                                    playTracks(startingAt: index)
                                }

                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .background(viewModel.backgroundColor.opacity(0.1))
                    .legibilityBackground(viewModel.backgroundColor)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func playTracks(startingAt index: Int, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }

        // Each song already knows which services it exists on, so this is a mapping rather
        // than a reconstruction. It replaced a ~65-line block that rebuilt a
        // SpotifySearchTrack, a FederatedSearchItem, a payload enum, and a stream-resolving
        // closure per track, on every tap.
        let refs = tracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }

        playbackCommands?.setQueue(refs, startIndex: index, shuffled: shuffled)
        playerPresentationController.expand()
    }
}

// MARK: - Subviews

private struct AlbumTrackRow: View {
    let index: Int
    let track: Song
    let onPlay: () -> Void

    var body: some View {
        Button {
            onPlay()
        } label: {
            VStack {
                HStack {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24, alignment: .leading)
                        .legibleForeground(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .lineLimit(1)
                            .legibleForeground(.primary)

                        Text(track.primaryArtistName ?? "")
                            .font(.caption)
                            .legibleForeground(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Group {
                        if track.isExplicit {
                            Image(systemName: "e.square.fill")
                                .legibleForeground(.secondary)
                        }

                        Menu {
                            Button {} label: {
                                Text("Download")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .legibleForeground(.secondary)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 20))
                }
                .fontWeight(.semibold)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
}
#endif
