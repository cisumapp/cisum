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
                Color.cisumBg

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
        // The iOS screen owns its whole viewport. macOS already hosts this inside the split
        // view's detail column, which opts out of the safe area itself — opting out again here
        // would reach past the column and start drawing under the sidebar.
        #if os(iOS)
        .ignoresSafeArea()
        #endif
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

    /// The canvas the artwork dissolves into.
    ///
    /// The blend gradients below have to fade to the exact colour painted behind them, so this
    /// is bound to the same token the screen's own background uses rather than to the extracted
    /// palette. Fading to the palette instead leaves a visible seam where the two disagree.
    private var canvas: Color {
        .cisumBg
    }

    /// Height of the artwork panel.
    ///
    /// Proportional rather than fixed so it keeps its relationship to the content below as the
    /// window resizes, and floored so a short window still gives the artwork room. The artwork
    /// itself is a square source, so this crops it to a wide band — which is what turns it from
    /// a cover into a header.
    private var artworkHeight: CGFloat {
        max(260, size.height * 0.56)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork
            blends
            actions
        }
        .frame(height: artworkHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Artwork

    private var artwork: some View {
        Group {
            if let artwork = artist.artworkURLString, let artworkURL = URL(string: artwork) {
                ArtworkImage(url: artworkURL, size: max(size.width, artworkHeight))
            }
        }
        .frame(width: size.width, height: artworkHeight)
        .clipped()
    }

    // MARK: - Blending

    /// Everything that stops the artwork reading as a rectangle laid on the canvas.
    ///
    /// Four layers, in the order they matter. The uniform scrim is the one that is easy to
    /// forget: without it the artwork sits at full brightness and the white title and action
    /// pills lose contrast against a pale image, and the whole panel reads as a bright poster
    /// rather than artwork sunk into a dark surface. The rest then shape the edges — the sides
    /// fade over a narrow strip so the panel bleeds off the column, and the bottom fade runs
    /// over a much taller distance so the artwork appears to sit *in* the surface and the
    /// content below rises out of it.
    private var blends: some View {
        ZStack {
            // Uniform scrim. Artwork is a photograph at whatever brightness the source
            // happens to be; this is what makes the panel's key consistent regardless, and
            // what keeps the overlaid type legible on top of it.
            Color.black.opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Palette wash, so the upper canvas carries the artwork's colour rather than
            // reading as flat black behind it.
            if let palette {
                LinearGradient(
                    colors: [palette.background.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: artworkHeight * 0.75, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            // Bottom: the long fade into the canvas. Weighted towards the end so the
            // artwork keeps its presence through the middle and then drops away quickly.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: canvas.opacity(0.3), location: 0.5),
                    .init(color: canvas.opacity(0.88), location: 0.82),
                    .init(color: canvas, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: artworkHeight * 0.62, alignment: .bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Sides: narrow, so only the outermost edge dissolves and the middle of the
            // artwork stays at full strength.
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [canvas, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: size.width * 0.06)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, canvas],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: size.width * 0.06)
            }

            // Top: just enough to stop the artwork meeting the window's edge abruptly.
            LinearGradient(
                colors: [canvas.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: artworkHeight * 0.14, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Title and actions

    private var actions: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text(artist.displayName)
                .font(.largeTitle)
                .bold()
                .foregroundStyle(palette?.title.safeTextColor(over: canvas) ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                actionButton("shuffle", label: nil) { onShuffle() }
                actionButton("play.fill", label: "Play") { onPlay() }
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    /// A pill that sits on the artwork, so it carries its own surface and hairline rather than
    /// relying on contrast against whatever image happens to be behind it.
    private func actionButton(_ symbol: String, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, label == nil ? 12 : 16)
            .frame(height: 32)
            .background(.black.opacity(0.32), in: .capsule)
            .overlay {
                Capsule().strokeBorder(Color.cisumChromeSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(label ?? "Shuffle")
    }
}
