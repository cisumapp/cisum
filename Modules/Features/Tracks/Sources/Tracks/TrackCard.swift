import Aesthetics
import SwiftUI

/// A song as a record: its cover is the sleeve, with the disc pulled part way out.
///
/// The disc is drawn rather than an image so it reads on any page. The old one was a black PNG,
/// near-invisible on the dark page, and only a sliver of it showed past the sleeve, so people
/// took it for a rendering glitch. It now has grooves, a sheen, a rim, the cover as its label and
/// a little wear at the edge, and it slides out of the sleeve when the card appears.
public struct TrackCard: View {
    let trackName: String
    let artistName: String
    let duration: String
    let artworkURL: URL?
    let artworkColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOut = false

    public init(
        trackName: String,
        artistName: String,
        duration: String = "",
        artworkURL: URL? = nil,
        artworkColor: Color = .cisumChromeSubtle
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.duration = duration
        self.artworkURL = artworkURL
        self.artworkColor = artworkColor
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

        VStack(alignment: .leading, spacing: 6 * scale) {
            ZStack(alignment: .leading) {
                VinylDisc(size: side, labelURL: artworkURL, seed: Self.seed(trackName + artistName))
                    .offset(x: isOut ? peek : 0)
                    .rotationEffect(.degrees(isOut ? 0 : -40))

                sleeve(side: side)
                    // The sleeve turns towards you as the disc comes out, so the card has depth.
                    .rotation3DEffect(
                        .degrees(isOut ? 0 : 16),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.5
                    )
            }
            .frame(width: side + peek, height: side, alignment: .leading)

            HStack {
                VStack(alignment: .leading) {
                    Text(trackName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(artistName)
                        .foregroundStyle(.textSecondary)
                        .font(.system(size: 10 * scale))
                        .fontWeight(.semibold)
                        .lineLimit(1)
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
                withAnimation(.spring(duration: 0.8, bounce: 0.22).delay(0.08)) { isOut = true }
            }
        }
    }

    private func sleeve(side: CGFloat) -> some View {
        Group {
            if let artworkURL {
                ArtworkImage(url: artworkURL, size: side)
            } else {
                artworkColor.opacity(0.3)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        // A printed edge, so the sleeve stays one object over the disc and on a matching page.
        .overlay { Rectangle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.35), radius: 5, x: 3, y: 2)
    }

    /// Stable across launches (`hashValue` is not), so a song keeps its scuffs.
    private static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// A record: grooves, sheen, rim, the cover as its label, and a few scuffs near the edge.
struct VinylDisc: View {
    let size: CGFloat
    let labelURL: URL?
    let seed: UInt64

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Lighter on the dark page than on the light one, so the disc never merges with it.
            Circle()
                .fill(colorScheme == .dark ? Color(hex: "#2F2F35") : Color(hex: "#1E1E22"))

            ForEach(0 ..< 16, id: \.self) { ring in
                Circle()
                    .strokeBorder(.white.opacity(ring.isMultiple(of: 4) ? 0.08 : 0.04), lineWidth: 0.5)
                    .padding(size * (0.04 + CGFloat(ring) * 0.0185))
            }

            // Light catching the grooves on two opposite quarters, as on a real record.
            Circle()
                .fill(AngularGradient(
                    colors: [.clear, .white.opacity(0.18), .clear, .clear, .white.opacity(0.12), .clear, .clear],
                    center: .center,
                    angle: .degrees(-30)
                ))
                .blendMode(.plusLighter)

            ForEach(scuffs, id: \.start) { scuff in
                Circle()
                    .trim(from: scuff.start, to: scuff.start + scuff.length)
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                    .padding(size * scuff.inset)
            }

            label

            Circle()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 2)
    }

    private var label: some View {
        ZStack {
            if let labelURL {
                ArtworkImage(url: labelURL, size: size * 0.36)
            } else {
                Color(hex: "#C9B98F")
            }
        }
        .frame(width: size * 0.36, height: size * 0.36)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
        .overlay {
            Circle()
                .fill(Color(hex: "#0D0D0F"))
                .frame(width: size * 0.035, height: size * 0.035)
        }
    }

    /// Three or four short marks near the rim, placed from the song so each disc has its own.
    private var scuffs: [(start: CGFloat, length: CGFloat, inset: CGFloat)] {
        var state = seed | 1
        func next() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 10000) / 10000
        }
        return (0 ..< (3 + Int(seed % 2))).map { _ in
            (start: next() * 0.9, length: 0.015 + next() * 0.035, inset: 0.012 + next() * 0.05)
        }
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
