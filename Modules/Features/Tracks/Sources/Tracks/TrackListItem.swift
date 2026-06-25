import Kingfisher
import SwiftUI
import Aesthetics

public struct TrackListItem: View {
    let trackName: String
    let artistName: String
    let duration: String
    let artworkURL: URL?
    let isExplicit: Bool

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
        let screenWidth = UIScreen.main.bounds.width
        let scale = ResponsiveLayout.DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)
        
        VStack(alignment: .leading) {
            HStack {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .downsampling(size: CGSize(width: 120, height: 120))
                        .scaledToFill()
                        .frame(width: 60 * scale, height: 60 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cisumChromeStrong)
                        .frame(width: 60 * scale, height: 60 * scale)
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
        .frame(height: 70 * scale)
        .padding(8 * scale)
        .contentShape(Rectangle())
    }
}

#Preview {
    TrackListItem(trackName: "Track Name", artistName: "Artist Name", duration: "4:20")
        .preferredColorScheme(.dark)
}
