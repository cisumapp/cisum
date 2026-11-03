import Aesthetics
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Loading placeholder matching `TrackListItem`'s layout 1:1, so a list fills in place rather
/// than jumping from a spinner to rows.
public struct TrackListItemSkeleton: View {
    public init() {}

    public var body: some View {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #elseif os(macOS)
        let screenWidth = NSScreen.main?.frame.width ?? 0
        #endif
        let scale = ResponsiveLayout.scaleFactor(forScreenWidth: screenWidth)
        #if os(macOS)
        let artwork = min(60 * scale, 56)
        let height = min(70 * scale, 72)
        #else
        let artwork = 60 * scale
        let height = 70 * scale
        #endif

        HStack {
            SkeletonBox()
                .frame(width: artwork, height: artwork)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBox(cornerRadius: 4)
                    .frame(width: 150 * scale, height: 12)
                SkeletonBox(cornerRadius: 4)
                    .frame(width: 90 * scale, height: 10)
            }

            Spacer()

            SkeletonBox(cornerRadius: 4)
                .frame(width: 30, height: 10)
                .padding(.trailing, 10 * scale)
        }
        .frame(height: height)
        .padding(8 * scale)
        .accessibilityHidden(true)
    }
}

/// A column of track skeletons with one shimmer across all of them, so the sweep stays in sync.
public struct TrackListSkeleton: View {
    let count: Int

    public init(count: Int = 6) {
        self.count = count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0 ..< count, id: \.self) { _ in
                TrackListItemSkeleton()
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

#Preview {
    TrackListSkeleton()
        .preferredColorScheme(.dark)
}
