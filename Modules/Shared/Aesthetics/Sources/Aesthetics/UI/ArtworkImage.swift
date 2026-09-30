//#if os(iOS)
import Kingfisher
import SwiftUI

/// Standard artwork image. Upgrades the URL to best quality (`ArtworkURL.best`), caches the
/// original once, and downsamples to the display size so the image is crisp AND fast to load.
/// Callers apply their own `.frame(...)` / `.clipShape(...)` as before.
public struct ArtworkImage: View {
    private let url: URL?
    private let pointSize: CGFloat

    /// - Parameter size: the square point size the image renders at; downsampling targets `size × screenScale` pixels.
    public init(url: URL?, size: CGFloat) {
        self.url = url
        self.pointSize = size
    }

    public var body: some View {
        #if os(iOS)
        let px = pointSize * UIScreen.main.scale
        #elseif os(macOS)
        let px = pointSize * (NSScreen.main?.backingScaleFactor ?? 1.0)
        #endif
        KFImage(ArtworkURL.best(from: url))
            .cacheOriginalImage()
            .downsampling(size: CGSize(width: px, height: px))
            .resizable()
            .scaledToFill()
    }
}
//#endif
