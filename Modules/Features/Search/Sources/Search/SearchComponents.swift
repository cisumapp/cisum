import Authentication
import Kingfisher
import Models
import SwiftUI
import Utilities
import YouTubeSDK

// MARK: - Spotify Track Row

// MARK: - Artist Row

public struct SearchArtistRow: View {
    let item: FederatedSearchItem

    public init(item: FederatedSearchItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 12) {
            KFImage(item.artworkURL)
                .downsampling(size: CGSize(width: 80, height: 80))
                .placeholder { Color.cisumChromeStrong }
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Artist: \(item.title)")
        .accessibilityHint("Double tap to view details")
    }
}
