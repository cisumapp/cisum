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
        ZStack {
            VStack(alignment: .leading) {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(artworkColor.opacity(0.3))
                        .frame(width: 140, height: 140)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text(trackName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(artistName)
                            .foregroundStyle(Color.secondary)
                            .font(.system(size: 10))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !duration.isEmpty {
                        Text(duration)
                            .foregroundStyle(Color.secondary)
                            .font(.system(size: 10))
                            .fontWeight(.semibold)
                            .padding(.trailing, 25)
                    }
                }
            }
            .background(
                ZStack {
                    Image.vinylGrooves
                        .resizable()
                        .frame(width: 140, height: 140)
                        .background {
                            Color.black
                                .mask {
                                    Image.vinylGrooves
                                        .resizable()
                                        .frame(width: 140, height: 140)
                                }
                        }
                    Image.vinylOverlay
                        .resizable()
                        .frame(width: 140, height: 140)
                    Image.vinylCenter
                        .resizable()
                        .frame(width: 140, height: 140)
                }
                .rotationEffect(.degrees(180))
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            )
            .frame(width: 160)
            .padding(8)
        }
//        .fontWidth(.expanded)
    }
}

#Preview {
    TrackCard(trackName: "Track Name", artistName: "Artist Name", duration: "4:20", artworkColor: .blue)
        .preferredColorScheme(.dark)
}
