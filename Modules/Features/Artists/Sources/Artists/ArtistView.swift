#if os(iOS)
import Aesthetics
import Kingfisher
import Models
import Player
import SwiftData
import SwiftUI
import YouTubeSDK

public struct ArtistView: View {
    let artist: Artist
    @State private var palette: ImageColorPalette?
    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController

    @Query private var topTracks: [Song]

    public init(artist: Artist) {
        self.artist = artist
        let artistID = artist.artistID
        _topTracks = Query(filter: #Predicate<Song> { $0.primaryArtistID == artistID })
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                (palette?.background ?? .pink)

                ScrollView {
                    ArtistArtworkHeader(
                        artist: artist,
                        palette: palette,
                        size: size,
                        onShuffle: {
                            if !topTracks.isEmpty {
                                playTracks(startingAt: Int.random(in: 0 ..< topTracks.count), shuffled: true)
                            }
                        },
                        onPlay: { playTracks(startingAt: 0) }
                    )
                    .task {
                        if let artwork = artist.artworkURLString, let artworkURL = URL(string: artwork) {
                            let tinyURL = ImageColorExtractor.paletteURL(from: artworkURL)
                            KingfisherManager.shared.retrieveImage(with: tinyURL) { result in
                                guard case let .success(value) = result,
                                      let data = value.image.pngData() else { return }

                                Task {
                                    let extractedPalette = await ImageColorExtractor.shared.extractPalette(from: data, cacheKey: artworkURL.absoluteString)
                                    await MainActor.run { palette = extractedPalette }
                                }
                            }
                        }
                    }

                    ArtistTopSongs(artist: artist, onPlayTrack: { index in
                        playTracks(startingAt: index)
                    })

                    ArtistDiscography(artist: artist)
                }
            }
            .legibilityBackground(palette?.background ?? .cisumBg)
        }
        .ignoresSafeArea()
    }

    private func playTracks(startingAt index: Int, shuffled: Bool = false) {
        guard !topTracks.isEmpty else { return }

        // Each song already knows which services it exists on, so this is a mapping rather
        // than a reconstruction. It replaced a ~65-line block that rebuilt a
        // SpotifySearchTrack, a FederatedSearchItem, a payload enum, and a stream-resolving
        // closure per track, on every tap.
        let refs = topTracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
        guard !refs.isEmpty else { return }

        playbackCommands?.setQueue(refs, startIndex: index, shuffled: shuffled)
        playerPresentationController.expand()
    }
}

// MARK: - Subviews

private struct ArtistArtworkHeader: View {
    let artist: Artist
    let palette: ImageColorPalette?
    let size: CGSize
    let onShuffle: () -> Void
    let onPlay: () -> Void

    var body: some View {
        if let artwork = artist.artworkURLString, let artworkURL = URL(string: artwork) {
            ArtworkImage(url: artworkURL, size: size.width)
                .frame(width: size.width, height: size.width)
                .clipped()
                .overlay {
                    ZStack {
                        LinearGradient(colors: [(palette?.background ?? .pink), (palette?.background ?? .pink).opacity(0.2), .clear, .clear, .clear, .clear], startPoint: .bottom, endPoint: .top)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                        HStack {
                            Text(artist.displayName)
                                .font(.largeTitle)
                                .bold()
                                .foregroundStyle(palette?.title.safeTextColor(over: palette?.background ?? .black) ?? .white)

                            Spacer()

                            Button {
                                onShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .padding()
                                    .background(
                                        Circle()
                                            .foregroundStyle(.black.opacity(0.2))
                                    )
                                    .foregroundStyle(palette?.background ?? .black)
                            }
                            .buttonStyle(.plain)

                            Button {
                                onPlay()
                            } label: {
                                Image(systemName: "play.fill")
                                    .padding()
                                    .background(
                                        Circle()
                                            .foregroundStyle(palette?.title.safeTextColor(over: palette?.background ?? .black) ?? .black)
                                    )
                                    .foregroundStyle(palette?.background ?? .white)
                                    .foregroundStyle((palette?.dominant ?? .pink).opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding()
                    }
                }
        }
    }
}
#endif
