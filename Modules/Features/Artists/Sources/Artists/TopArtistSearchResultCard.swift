//
//  TopArtistSearchResultCard.swift
//  Artists
//
//  Created by Aarav Gupta on 29/04/26.
//

#if os(iOS)
import Kingfisher
import SwiftUI

/// The artist a search names: their photo with the name over it and a row of their covers.
public struct TopArtistSearchResultCard: View {
    let artistName: String
    let artistImageURL: URL?
    /// Covers along the bottom; up to five are shown.
    let previewArtworkURLs: [URL?]

    public init(artistName: String, artistImageURL: URL?, previewArtworkURLs: [URL?]) {
        self.artistName = artistName
        self.artistImageURL = artistImageURL
        self.previewArtworkURLs = previewArtworkURLs
    }

    public var body: some View {
        Color.gray.opacity(0.3)
            .aspectRatio(7 / 6, contentMode: .fit)
            .overlay {
                KFImage(artistImageURL)
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                ZStack {
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )

                    VStack {
                        Text(artistName)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                        HStack {
                            ForEach(Array(previewArtworkURLs.prefix(5).enumerated()), id: \.offset) { _, url in
                                ArtistResultAlbumPreview(artworkURL: url)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }
            }
            .clipShape(.rect(cornerRadius: 24))
    }
}

struct ArtistResultAlbumPreview: View {
    let artworkURL: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.gray)
            .frame(width: 70, height: 70)
            .overlay {
                KFImage(artworkURL)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(.rect(cornerRadius: 12))
    }
}

#Preview {
    let url = URL(string: "https://yt3.googleusercontent.com/_c4JMCiDeaC2RRfShXddOuIV_A7oCL4m1R6-YK-3TDlsYgNQTXwxV0f-TTJrsO1StMt07qW3O6XNPSNt=w544-h544-l90-rj")!

    ScrollView {
        TopArtistSearchResultCard(artistName: "Kendrick Lamar", artistImageURL: url, previewArtworkURLs: Array(repeating: nil, count: 5))
            .padding(16)
    }
}
#endif
