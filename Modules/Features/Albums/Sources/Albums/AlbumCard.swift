import Aesthetics
import Kingfisher
import Models
import Player
import SwiftData
import SwiftUI
import Tracks
import YouTubeSDK

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct AlbumCard: View {
    @State private var viewModel = AlbumViewModel()
    public let album: Album

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.motionArtwork) private var motionArtwork

    @Query private var songs: [Song]
    /// Set for an album that is not in the library: its tracks load when the card opens.
    let remote: RemoteAlbum?

    public init(album: Album) {
        self.album = album
        self.remote = nil
        let albumID = album.albumID
        _songs = Query(filter: #Predicate<Song> { $0.albumID == albumID })
    }

    /// An album that is not in the library. It looks and opens like a saved one; its tracks are
    /// loaded the first time it opens.
    public init(remote: RemoteAlbum) {
        // Unsaved: SwiftData models work as plain values until they are inserted.
        let album = Album(
            albumID: "remote:\(remote.sourceID)",
            title: remote.title,
            normalizedTitle: remote.title.lowercased(),
            primaryArtistName: remote.artist,
            artworkURLString: remote.artworkURL?.absoluteString,
            releaseDateString: remote.year
        )
        self.album = album
        self.remote = remote
        let albumID = album.albumID
        _songs = Query(filter: #Predicate<Song> { $0.albumID == albumID })
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
                    AlbumCover(isCardExpanded: isCardExpanded, viewModel: viewModel, album: album)
                }
            } content: { _, _ in
                Group {
                if let remote {
                    RemoteAlbumTrackList(album: album, remote: remote)
                } else {
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
                }
                // Opening an album fetches its animated artwork, so playing it later finds the
                // video waiting. Keyed like the player's request: artist and album.
                .task {
                    let request = MotionArtworkRequest(title: album.title, artist: album.primaryArtistName ?? "", album: album.title)
                    _ = await motionArtwork?.fetch(request)
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

/// An album that is not in the library, and where its tracks come from.
public struct RemoteAlbum {
    public let title: String
    public let artist: String?
    public let year: String?
    public let artworkURL: URL?
    public let sourceID: String
    /// Fetches the tracks; called the first time the card opens.
    public let loadTracks: @MainActor () async -> [IncomingTrack]

    public init(
        title: String,
        artist: String?,
        year: String?,
        artworkURL: URL?,
        sourceID: String,
        loadTracks: @escaping @MainActor () async -> [IncomingTrack]
    ) {
        self.title = title
        self.artist = artist
        self.year = year
        self.artworkURL = artworkURL
        self.sourceID = sourceID
        self.loadTracks = loadTracks
    }
}

/// A remote album's track list: the saved card's layout, filled once the tracks arrive.
private struct RemoteAlbumTrackList: View {
    let album: Album
    let remote: RemoteAlbum

    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @State private var tracks: [PlaylistItem]?

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: 1900)
                .contentShape(.rect)

            LazyVStack(alignment: .leading, spacing: 4) {
                if let tracks {
                    if tracks.isEmpty {
                        Text("No tracks found")
                            .legibleForeground(.secondary)
                            .padding()
                    }
                    ForEach(Array(tracks.enumerated()), id: \.element.itemKey) { index, track in
                        Button {
                            play(startingAt: index)
                        } label: {
                            TrackListItem(
                                trackName: track.title,
                                // Album tracks from YouTube Music come with an empty artist.
                                artistName: track.artistName.flatMap { $0.isEmpty ? nil : $0 } ?? album.primaryArtistName ?? "",
                                duration: track.durationSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "",
                                artworkURL: (track.artworkURLString ?? album.artworkURLString).flatMap { URL(string: $0) }
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.horizontal)
                    }
                } else {
                    TrackListSkeleton(count: 8)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
            .animation(.easeOut(duration: 0.3), value: tracks == nil)
        }
        .task {
            guard tracks == nil else { return }
            let id = album.albumID
            tracks = await remote.loadTracks().enumerated().map { index, track in
                PlaylistItem(remote: track, playlistID: id, sortIndex: index)
            }
        }
    }

    private func play(startingAt index: Int) {
        guard let tracks else { return }
        let refs = tracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }
        let selected = tracks[index].playableRef(preferring: preferredSourceIDs)
        playbackCommands?.setQueue(refs, startIndex: selected.flatMap { refs.firstIndex(of: $0) } ?? 0, shuffled: false)
        playerPresentationController.expand()
    }
}

#if DEBUG
#Preview {
    AlbumCard(album: Album(title: "Bad", normalizedTitle: "Bad"))
}
#endif
