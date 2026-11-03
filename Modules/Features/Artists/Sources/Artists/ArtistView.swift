import Aesthetics
import Albums
import Catalog
import Kingfisher
import Models
import Player
import SwiftData
import Playlists
import SwiftUI
import Utilities
import YouTubeSDK

public struct ArtistView: View {
    let artist: Artist
    @State private var palette: ImageColorPalette?
    /// The title row has scrolled under the toolbar, so its buttons are shown there instead.
    @State private var isTitleRowHidden = false
    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.preferredSourceIDs) private var preferredSourceIDs
    @Environment(PlayerPresentationController.self) private var playerPresentationController
    @Environment(\.catalog) private var catalog
    @Environment(\.artistPageStore) private var pageStore
    /// The hero photo, chosen once when the page opens and kept for the visit, so it never
    /// re-crops or reloads in front of the user, and the palette is always read from it.
    @State private var heroURL: URL?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) private var router
    /// The artist's page from the Catalog; `nil` until it arrives.
    @State private var catalogArtist: CatalogArtist?
    @State private var isLoadingCatalog = true

    @Query private var topTracks: [Song]

    public init(artist: Artist) {
        self.artist = artist
        let artistID = artist.artistID
        _topTracks = Query(filter: #Predicate<Song> { $0.primaryArtistID == artistID })
        _heroURL = State(initialValue: (artist.bannerURLString ?? artist.artworkURLString).flatMap(URL.init(string:)))
    }

    public var body: some View {
        GeometryReader { geo in
            let heroHeight = max(260, geo.size.height * 0.56)
            // The title row sits 80pt up into the hero; its buttons hand over to the toolbar as
            // the row reaches it.
            PaletteScrollView(
                palette: palette,
                heroHeight: heroHeight,
                isScrolledPast: $isTitleRowHidden,
                scrolledPastOffset: heroHeight - 180
            ) {
                ArtistArtworkHeader(artist: artist, photoURL: heroURL, palette: palette, size: geo.size)
            } content: {
                // Lifted over the hero's faded bottom edge, where the name used to sit inside it.
                ArtistTitleRow(artist: artist, onShuffle: shuffle, onPlay: { playTracks(startingAt: 0) })
                    .padding(.top, -80)

                sections
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isTitleRowHidden {
                    Button("Shuffle", systemImage: "shuffle", action: shuffle)
                    Button("Play", systemImage: "play.fill") { playTracks(startingAt: 0) }
                }
            }
        }
        .task(id: artist.artistID) {
            await loadCatalog()
        }
        .task(id: heroURL) {
            // From the photo on screen, so the page's colours always belong to it.
            guard let heroURL else { return }
            let tinyURL = ImageColorExtractor.paletteURL(from: heroURL)
            guard let value = try? await KingfisherManager.shared.retrieveImage(with: tinyURL),
                  let data = value.image.pngData()
            else { return }
            palette = await ImageColorExtractor.shared.extractPalette(from: data, cacheKey: heroURL.absoluteString)
        }
        // The iOS screen owns its whole viewport. macOS already hosts this inside the split
        // view's detail column, which opts out of the safe area itself — opting out again here
        // would reach past the column and start drawing under the sidebar.
        #if os(iOS)
        .ignoresSafeArea()
        #endif
    }

    // MARK: - Sections

    /// The Catalog's page once it arrives, a skeleton of it until then, and the library's own
    /// songs and albums whenever the Catalog has nothing.
    @ViewBuilder
    private var sections: some View {
        Group {
            if let catalogArtist {
                catalogSections(catalogArtist)
            } else if isLoadingCatalog, topTracks.isEmpty {
                ArtistPageSkeleton()
            } else {
                librarySections
            }
        }
        .animation(.easeOut(duration: 0.35), value: catalogArtist == nil)
    }

    @ViewBuilder
    private var librarySections: some View {
        ArtistTopSongs(artist: artist, onPlayTrack: { index in
            playTracks(startingAt: index)
        })
        ArtistDiscography(artist: artist)
    }

    @ViewBuilder
    private func catalogSections(_ page: CatalogArtist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.topSongs.isEmpty {
                ArtistTopSongs(artist: artist, onPlayTrack: { index in
                    playTracks(startingAt: index)
                })
            } else {
                ArtistCatalogSongs(tracks: Array(page.topSongs.prefix(5))) { index in
                    playTracks(startingAt: index)
                }
            }

            if page.albums.isEmpty {
                ArtistDiscography(artist: artist)
            } else {
                ArtistShelf(title: "Albums") {
                    ForEach(page.albums) { AlbumCard(remote: RemoteAlbum($0, artist: page.name, catalog: catalog)) }
                }
            }

            if !page.singles.isEmpty {
                ArtistShelf(title: "Singles & EPs") {
                    ForEach(page.singles) { AlbumCard(remote: RemoteAlbum($0, artist: page.name, catalog: catalog)) }
                }
            }

            if !page.playlists.isEmpty {
                ArtistShelf(title: "Playlists") {
                    ForEach(page.playlists) { PlaylistCard(remote: RemotePlaylist($0, catalog: catalog)) }
                }
            }

            if !page.similar.isEmpty {
                ArtistShelf(title: "Fans Also Like") {
                    ForEach(page.similar) { similar in
                        MediaTile(url: similar.photoURL, title: similar.name, subtitle: similar.audience, shape: .round) {
                            let next = Artist.findOrInsert(
                                youtubeBrowseID: similar.youtubeBrowseID, name: similar.name,
                                artworkURL: similar.photoURL, in: modelContext
                            )
                            router.navigate(to: .artist(id: next.artistID))
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }

            if let about = page.about, !about.isEmpty {
                ArtistAbout(text: about)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Data

    /// The page saved on the device opens at once; it is fetched again only when it has gone
    /// stale, and the overnight refresh usually does that first.
    private func loadCatalog() async {
        guard let pageStore else {
            isLoadingCatalog = false
            return
        }
        if let saved = pageStore.savedPage(for: artist) {
            catalogArtist = saved
            isLoadingCatalog = false
            guard pageStore.isStale(artist) else { return }
        }
        let page = await pageStore.refresh(artist)
        // An artist with no photo at all takes the banner now; otherwise it is the next visit's.
        if heroURL == nil { heroURL = page.photoURL }
        withAnimation(.easeOut(duration: 0.35)) {
            catalogArtist = page
            isLoadingCatalog = false
        }
    }

    /// The Catalog's top songs once loaded, the library's songs before then.
    private var playableRefs: [PlayableRef] {
        if let songs = catalogArtist?.topSongs, !songs.isEmpty {
            return songs.enumerated().compactMap { index, track in
                PlaylistItem(remote: track.incoming, playlistID: "artist:\(artist.artistID)", sortIndex: index)
                    .playableRef(preferring: preferredSourceIDs)
            }
        }
        // Each song already knows which services it exists on, so this is a mapping rather
        // than a reconstruction.
        return topTracks.compactMap { $0.playableRef(preferring: preferredSourceIDs) }
    }

    private func shuffle() {
        let count = playableRefs.count
        guard count > 0 else { return }
        playTracks(startingAt: Int.random(in: 0 ..< count), shuffled: true)
    }

    private func playTracks(startingAt index: Int, shuffled: Bool = false) {

        let refs = playableRefs
        guard refs.indices.contains(index) else { return }

        playbackCommands?.setQueue(refs, startIndex: index, shuffled: shuffled)
        playerPresentationController.expand()
    }
}

// MARK: - Subviews

private struct ArtistArtworkHeader: View {
    let artist: Artist
    let photoURL: URL?
    let palette: ImageColorPalette?
    let size: CGSize

    /// The canvas the artwork dissolves into.
    ///
    /// The blend gradients below have to fade to the exact colour painted behind them, and the
    /// page is painted in the palette's background (`PaletteScrollView`), so this is that colour.
    private var canvas: Color {
        palette?.background ?? .cisumBg
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
        }
        .frame(height: artworkHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Artwork

    private var artwork: some View {
        Group {
            if let artworkURL = photoURL {
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
}

/// The name and the Play and Shuffle pills. Part of the page, not the hero: it scrolls away
/// while the photo holds still, and its buttons move into the toolbar once it has gone.
private struct ArtistTitleRow: View {
    let artist: Artist
    let onShuffle: () -> Void
    let onPlay: () -> Void

    var body: some View {
        actions
    }

    private var actions: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text(artist.displayName)
                .font(.largeTitle)
                .bold()
                .legibleForeground(.primary)
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
