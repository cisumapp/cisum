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

// MARK: - Playlist Row

public struct SearchPlaylistRow: View {
    let item: FederatedSearchItem
    let isImporting: Bool

    public init(item: FederatedSearchItem, isImporting: Bool) {
        self.item = item
        self.isImporting = isImporting
    }

    public var body: some View {
        HStack(spacing: 12) {
            KFImage(item.artworkURL)
                .downsampling(size: CGSize(width: 100, height: 100))
                .placeholder {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isImporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playlist: \(item.title) by \(item.subtitle)")
        .accessibilityHint(isImporting ? "Importing playlist" : "Double tap to open")
    }
}

// MARK: - Federated Row

// MARK: - Supporting Components

public struct SearchBadge: View {
    let title: String
    let tint: Color
    let textColor: Color

    public init(title: String, tint: Color, textColor: Color) {
        self.title = title
        self.tint = tint
        self.textColor = textColor
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(textColor)
            .accessibilityLabel(title)
    }
}

public struct SearchMetadataBadges: View {
    let item: FederatedSearchItem

    public init(item: FederatedSearchItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 6) {
            SearchBadge(
                title: item.service.rawValue, tint: .secondary.opacity(0.12), textColor: .secondary
            )

            if item.isExplicit {
                SearchBadge(title: "Explicit", tint: .red.opacity(0.16), textColor: .red)
            }

            if let quality = item.audioQualityLabel {
                SearchBadge(title: quality, tint: .blue.opacity(0.14), textColor: .blue)
            }

            if let codec = item.audioCodecLabel {
                SearchBadge(title: codec, tint: .secondary.opacity(0.16), textColor: .secondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

public struct SearchSectionHeader: View {
    let title: String
    let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

