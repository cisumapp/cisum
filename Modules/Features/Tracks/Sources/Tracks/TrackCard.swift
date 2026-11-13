import Aesthetics
import SwiftUI

/// A song as a record: the cover is the sleeve, and the disc rolls part way out of it.
///
/// The disc is the player's `VinylDisk` — the same groove, gloss and spindle assets — on black
/// vinyl, so a card's record is the record the player spins. The light groove texture keeps it
/// visible on the dark page.
public struct TrackCard: View {
    let trackName: String
    let artistName: String
    let duration: String
    let artworkURL: URL?
    let artworkColor: Color
    let isExplicit: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOut = false

    public init(
        trackName: String,
        artistName: String,
        duration: String = "",
        artworkURL: URL? = nil,
        artworkColor: Color = .cisumChromeSubtle,
        isExplicit: Bool = false
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.duration = duration
        self.artworkURL = artworkURL
        self.artworkColor = artworkColor
        self.isExplicit = isExplicit
    }

    public var body: some View {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #elseif os(macOS)
        let screenWidth = NSScreen.main?.frame.width ?? 0
        #endif
        let scale = ResponsiveLayout.scaleFactor(forScreenWidth: screenWidth)
        // 174pt wide in all: two cards and their spacing fit a phone's Home grid.
        let side = 138 * scale
        let peek = 28 * scale
        // Rolling, not sliding: the disc turns by exactly the distance it travels.
        let roll = Double(peek / (.pi * side)) * 360

        VStack(alignment: .leading, spacing: 6 * scale) {
            ZStack(alignment: .leading) {
                VinylDisk(size: side, rotation: isOut ? roll : 0, grooveOpacity: 0.8) {
                    Color.black
                }
                .offset(x: isOut ? peek : 0)

                sleeve(side: side)
            }
            .frame(width: side + peek, height: side, alignment: .leading)

            HStack {
                VStack(alignment: .leading) {
                    Text(trackName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        if isExplicit { ExplicitBadge() }
                        Text(artistName)
                            .foregroundStyle(.textSecondary)
                            .font(.system(size: 10 * scale))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !duration.isEmpty {
                    Text(duration)
                        .foregroundStyle(.textSecondary)
                        .font(.system(size: 10 * scale))
                        .fontWeight(.semibold)
                        .padding(.trailing, peek)
                }
            }
            .frame(width: side + peek)
        }
        .padding(4 * scale)
        .onAppear {
            guard !isOut else { return }
            if reduceMotion {
                isOut = true
            } else {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) { isOut = true }
            }
        }
    }

    private func sleeve(side: CGFloat) -> some View {
        ZStack {
            // Under the cover, so the sleeve is there before the image loads and a card scrolled
            // in never shows a bare disc.
            Color.surfaceRaised
            if let artworkURL {
                ArtworkImage(url: artworkURL, size: side)
            } else {
                artworkColor.opacity(0.3)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .shadow(color: .black.opacity(0.3), radius: 5, x: 3, y: 3)
    }
}

#Preview {
    HStack {
        TrackCard(trackName: "Track Name", artistName: "Artist Name", duration: "4:20")
        TrackCard(trackName: "Another", artistName: "Artist Name")
    }
    .padding()
    .background(Color.surfaceBackground)
}
