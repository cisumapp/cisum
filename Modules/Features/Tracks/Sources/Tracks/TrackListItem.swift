import Kingfisher
import SwiftUI

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
        VStack(alignment: .leading) {
            HStack {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .downsampling(size: CGSize(width: 120, height: 120))
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cisumChromeStrong)
                        .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading) {
                    Text(trackName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if isExplicit {
                            Image(systemName: "e.square.fill")
                                .foregroundStyle(Color.secondary)
                                .font(.system(size: 10))
                        }

                        Text(artistName)
                            .foregroundStyle(Color.secondary)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if !duration.isEmpty {
                        Text(duration)
                            .foregroundStyle(Color.secondary)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Image(systemName: "ellipsis")
                        .font(.title2)
                }
                .padding(.trailing, 10)
            }
        }
        .frame(height: 70)
        .padding(8)
        .contentShape(Rectangle())
//        .fontWidth(.expanded)
    }
}

#Preview {
    TrackListItem(trackName: "Track Name", artistName: "Artist Name", duration: "4:20")
        .preferredColorScheme(.dark)
}
