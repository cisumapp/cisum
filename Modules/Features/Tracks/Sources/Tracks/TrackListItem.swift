import Aesthetics
import SwiftUI

#if os(macOS)
import AppKit
#endif

public struct TrackListItem: View {
    let trackName: String
    let artistName: String
    let duration: String
    let artworkURL: URL?
    let isExplicit: Bool

    #if os(macOS)
    /// Artwork never grows past this on macOS.
    static let maxArtworkSide: CGFloat = 56
    /// Row height ceiling for macOS.
    static let maxRowHeight: CGFloat = 72
    /// Widest the row may get before its content centres instead of stretching.
    static let maxRowWidth: CGFloat = 900
    #endif

    public init(
        trackName: String,
        artistName: String,
        duration: String = "",
        artworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.duration = duration
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
    }

    public var body: some View {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #elseif os(macOS)
        let screenWidth = NSScreen.main?.frame.width ?? 0
        #endif
        let scale = ResponsiveLayout.scaleFactor(forScreenWidth: screenWidth)

        VStack(alignment: .leading) {
            HStack {
                if let artworkURL {
                    ArtworkImage(url: artworkURL, size: artworkSide(scale))
                        .frame(width: artworkSide(scale), height: artworkSide(scale))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cisumChromeStrong)
                        .frame(width: artworkSide(scale), height: artworkSide(scale))
                }

                VStack(alignment: .leading) {
                    Text(trackName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .legibleForeground(.primary)

                    HStack(spacing: 4) {
                        if isExplicit {
                            Image(systemName: "e.square.fill")
                                .legibleForeground(.secondary)
                                .font(.system(size: 10 * scale))
                        }

                        Text(artistName)
                            .legibleForeground(.secondary)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 10 * scale) {
                    if !duration.isEmpty {
                        Text(duration)
                            .legibleForeground(.secondary)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .legibleForeground(.secondary)
                }
                .padding(.trailing, 10 * scale)
            }
        }
        .frame(height: rowHeight(scale))
        .padding(8 * scale)
        #if os(macOS)
        // Ceiling: the row must not grow with the window. `frame(maxWidth:)` centres the
        // content once the window is wider than this.
        .frame(maxWidth: Self.maxRowWidth)
        #endif
        .contentShape(Rectangle())
    }

    private func artworkSide(_ scale: CGFloat) -> CGFloat {
        #if os(macOS)
        min(60 * scale, Self.maxArtworkSide)
        #else
        60 * scale
        #endif
    }

    private func rowHeight(_ scale: CGFloat) -> CGFloat {
        #if os(macOS)
        min(70 * scale, Self.maxRowHeight)
        #else
        70 * scale
        #endif
    }
}

#Preview {
    TrackListItem(trackName: "Track Name", artistName: "Artist Name", duration: "4:20")
        .preferredColorScheme(.dark)
}
