import Aesthetics
import Kingfisher
import SwiftUI

public struct TrackCard: View {
    let trackName: String
    let artistName: String
    let duration: String
    let artworkURL: URL?
    let artworkColor: Color

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
        let screenWidth = UIScreen.main.bounds.width
        let scale = ResponsiveLayout.DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)
        
        ZStack {
            VStack(alignment: .leading) {
                if let artworkURL {
                    KFImage(artworkURL)
                        .downsampling(size: CGSize(width: 280, height: 280))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140 * scale, height: 140 * scale)
                        .clipped()
                        .shadow(radius: 5, x: 3, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(artworkColor.opacity(0.3))
                        .frame(width: 140 * scale, height: 140 * scale)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text(trackName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(artistName)
                            .foregroundStyle(Color.secondary)
                            .font(.system(size: 10 * scale))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !duration.isEmpty {
                        Text(duration)
                            .foregroundStyle(Color.secondary)
                            .font(.system(size: 10 * scale))
                            .fontWeight(.semibold)
                            .padding(.trailing, 25 * scale)
                    }
                }
            }
            .background(
                ZStack {
                    Image.vinylGrooves
                        .resizable()
                        .frame(width: 140 * scale, height: 140 * scale)
                        .background {
                            Color.black
                                .mask {
                                    Image.vinylGrooves
                                        .resizable()
                                        .frame(width: 140 * scale, height: 140 * scale)
                                }
                        }
                    Image.vinylOverlay
                        .resizable()
                        .frame(width: 140 * scale, height: 140 * scale)
                    Image.vinylCenter
                        .resizable()
                        .frame(width: 140 * scale, height: 140 * scale)
                }
                .rotationEffect(.degrees(180))
                .frame(width: 140 * scale, height: 140 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            )
            .frame(width: 160 * scale)
            .padding(8 * scale)
        }
    }
}

#Preview {
    TrackCard(trackName: "Track Name", artistName: "Artist Name", duration: "4:20", artworkColor: .blue)
        .preferredColorScheme(.dark)
}
