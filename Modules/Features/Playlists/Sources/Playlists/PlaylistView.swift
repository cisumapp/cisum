//
//  PlaylistView.swift
//  Playlists
//
//  Created by Aarav Gupta on 29/04/26.
//

import Aesthetics
import Kingfisher
import Models
import Player
import ProviderSDK
import SwiftData
import SwiftUI
import YouTubeSDK

public struct PlaylistView: View {
    let playlist: Models.Playlist
    @Query private var tracks: [PlaylistItem]

    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    @Environment(\.searchViewModel) private var searchViewModel
    @Environment(\.playerViewModel) private var playerViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showPlaybackAlert = false
    @State private var playbackAlertMessage = ""

    public init(playlist: Models.Playlist) {
        self.playlist = playlist
        let playlistID = playlist.playlistID
        _tracks = Query(
            filter: #Predicate<PlaylistItem> { $0.playlistID == playlistID },
            sort: \.sortIndex
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                LinearGradient(
                    colors: [
                        .black,
                        playerViewModel.currentAccentColor,
                        playerViewModel.currentAccentColor,
                        playerViewModel.currentAccentColor,
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )

                ScrollView {
                    PlaylistArtworkHeader(playlist: playlist, width: size.width)

                    HStack {
                        Button {
                            Task {
                                await playPlaylist(startingAt: 0)
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 50)
                                    .fill(playerViewModel.currentAccentColor)

                                Text("Play")
                                    .foregroundStyle(Color.cisumBg)
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(width: 160, height: 48)
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical)

                    LazyVStack(spacing: 0) {
                        ForEach(tracks, id: \.itemKey) { track in
                            let index = tracks.firstIndex(where: { $0.itemKey == track.itemKey }) ?? 0
                            PlaylistTrackRow(index: index, track: track) {
                                Task {
                                    await playPlaylist(startingAt: index)
                                }
                            }

                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .alert(playbackAlertMessage, isPresented: $showPlaybackAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func playPlaylist(startingAt index: Int) async {
        guard tracks.indices.contains(index) else { return }

        let queueTracks = tracks.compactMap { makePlayableQueueTrack(for: $0) }
        guard !queueTracks.isEmpty else {
            playbackAlertMessage = "This playlist does not have any playable tracks yet."
            showPlaybackAlert = true
            return
        }

        let selectedItem = tracks[index]
        let selectedMediaID = playbackMediaID(for: selectedItem)
        guard let startIndex = queueTracks.firstIndex(where: { $0.mediaID == selectedMediaID })
        else {
            playbackAlertMessage = "Unable to start playback for the selected track."
            showPlaybackAlert = true
            return
        }

        playerViewModel.setQueue(queueTracks, startIndex: startIndex)
        playerPresentationController.expand()
    }

    private func makePlayableQueueTrack(for track: PlaylistItem) -> ExternalQueueTrack {
        let artworkURL = track.artworkURLString.flatMap { URL(string: $0) }
        let searchItem = makeSearchItem(for: track, artworkURL: artworkURL)
        let itemKey = track.itemKey
        let store = playlistLibraryStore

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
                    await store?.updateProviderID(for: itemKey, provider: resolved.service.rawValue, trackID: resolved.mediaID)
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
            let rep = TrackRepresentation(providerID: "tidal", providerTrackID: tidalID, title: track.title, artist: artistName, duration: duration, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: tidalID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "tidal", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "tidal", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "tidal", value: artistName), name: artistName)),
                duration: duration ?? 0,
                representations: [rep]
            )
            payload = .providerSDKTrack(sdkTrack)
        } else if let qobuzID = validID(track.qobuzID) {
            mediaID = qobuzID
            let rep = TrackRepresentation(providerID: "qobuz", providerTrackID: qobuzID, title: track.title, artist: artistName, duration: duration, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: qobuzID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "qobuz", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "qobuz", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "qobuz", value: artistName), name: artistName)),
                duration: duration ?? 0,
                representations: [rep]
            )
            payload = .providerSDKTrack(sdkTrack)
        } else if let appleID = validID(track.appleMusicID) {
            mediaID = appleID
            let rep = TrackRepresentation(providerID: "appleMusic", providerTrackID: appleID, title: track.title, artist: artistName, duration: duration, artworkURL: artworkURL)
            let sdkTrack = Track(
                id: CanonicalID(value: appleID),
                title: track.title,
                artists: [Artist(id: ArtistIdentifier(provider: "appleMusic", value: artistName), name: artistName)],
                album: Album(id: AlbumIdentifier(provider: "appleMusic", value: track.albumName ?? ""), title: track.albumName ?? "", artist: Artist(id: ArtistIdentifier(provider: "appleMusic", value: artistName), name: artistName)),
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
            if let ytVideo {
                payload = .youtubeVideo(ytVideo)
            } else {
                return makeFallbackSpotifyItem(for: track, artworkURL: artworkURL)
            }
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
            if let youtubeVideo {
                payload = .youtubeVideo(youtubeVideo)
            } else {
                return makeFallbackSpotifyItem(for: track, artworkURL: artworkURL)
            }
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

    private func makeFallbackSpotifyItem(for track: PlaylistItem, artworkURL: URL?)
        -> FederatedSearchItem
    {
        let artistName = track.artistName ?? ""
        let spotifyID = track.sourceTrackID ?? track.itemKey
        let spotifyTrack = SpotifySearchTrack(
            id: spotifyID,
            title: track.title,
            artistName: artistName,
            albumName: track.albumName,
            artworkURL: artworkURL,
            durationSeconds: track.durationSeconds ?? 0,
            previewURL: nil,
            isrc: track.isrc
        )

        return FederatedSearchItem(
            id: "spotify-\(spotifyID)",
            title: track.title,
            subtitle: artistName.isEmpty ? (track.albumName ?? "Spotify") : artistName,
            artworkURL: artworkURL,
            durationSeconds: track.durationSeconds,
            isPlayable: true,
            isExplicit: false,
            audioQualityLabel: nil,
            audioCodecLabel: nil,
            payload: .spotify(spotifyTrack)
        )
    }

    private func makeSyntheticYouTubeVideo(
        videoID: String,
        title: String,
        author: String,
        durationSeconds: Double?,
        artworkURL: URL?
    ) -> YouTubeVideo? {
        var videoDetails: [String: Any] = [
            "videoId": videoID,
            "title": title,
            "viewCount": "0",
            "author": author,
            "channelId": "",
            "shortDescription": "",
        ]

        if let durationSeconds {
            videoDetails["lengthSeconds"] = String(Int(durationSeconds))
        }

        if let artworkURL {
            videoDetails["thumbnail"] = [
                "thumbnails": [
                    ["url": artworkURL.absoluteString, "width": 0, "height": 0],
                ],
            ]
        }

        let root: [String: Any] = ["videoDetails": videoDetails]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root)
        else {
            return nil
        }

        return try? JSONDecoder().decode(YouTubeVideo.self, from: data)
    }
}

// MARK: - Subviews

private struct PlaylistArtworkHeader: View {
    let playlist: Models.Playlist
    let width: CGFloat
    @Environment(\.playerViewModel) private var playerViewModel

    var body: some View {
        Rectangle()
            .fill(playerViewModel.currentAccentColor)
            .frame(width: width, height: width)
            .overlay {
                if let artwork = playlist.artworkURLString,
                   let artworkURL = URL(string: artwork)
                {
                    KFImage(artworkURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: width)
                        .clipped()
                }
            }
            .overlay {
                VStack(alignment: .leading) {
                    Text(playlist.title)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    if let owner = playlist.ownerName {
                        Button {} label: {
                            HStack(spacing: 4) {
                                Text(owner)
                                    .textCase(.uppercase)

                                Image(systemName: "chevron.right")
                                    .font(.callout)
                            }
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading
                )
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear], startPoint: .bottom,
                        endPoint: .center
                    )
                )
            }
    }
}

private struct PlaylistTrackRow: View {
    let index: Int
    let track: PlaylistItem
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .lineLimit(1)

                        Text(track.artistName ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Group {
                        Menu {
                            Button {} label: {
                                Text("Download")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
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

#Preview {
    PlaylistView(playlist: Models.Playlist(title: "tera sharmana", normalizedTitle: "tera sharmana"))
}
