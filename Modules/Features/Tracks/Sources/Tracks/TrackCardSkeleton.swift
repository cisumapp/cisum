import Aesthetics
import SwiftUI

/// Loading placeholder matching `TrackCard`'s layout 1:1 so the grid doesn't jump when data lands.
public struct TrackCardSkeleton: View {
    public init() {}

    public var body: some View {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #elseif os(macOS)
        let screenWidth = NSScreen.main?.frame.width ?? 0
        #endif
        let scale = ResponsiveLayout.scaleFactor(forScreenWidth: screenWidth)

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
