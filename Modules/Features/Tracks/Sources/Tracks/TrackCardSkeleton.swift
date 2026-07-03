import Aesthetics
import SwiftUI

/// Loading placeholder matching `TrackCard`'s layout 1:1 so the grid doesn't jump when data lands.
public struct TrackCardSkeleton: View {
    public init() {}

    public var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let scale = ResponsiveLayout.DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)

        VStack(alignment: .leading) {
            SkeletonBox(cornerRadius: 0)
                .frame(width: 140 * scale, height: 140 * scale)

            HStack {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    SkeletonBox()
                        .frame(width: 90 * scale, height: 10 * scale)
                    SkeletonBox()
                        .frame(width: 60 * scale, height: 8 * scale)
                }

                Spacer()
            }
        }
        .frame(width: 160 * scale)
        .padding(8 * scale)
        .shimmering()
    }
}

#Preview {
    TrackCardSkeleton()
        .preferredColorScheme(.dark)
}
