#if os(iOS)
import Kingfisher

/// One-time Kingfisher configuration for the artwork pipeline.
public enum ArtworkPipeline {
    /// Call once at launch. Sets cache limits and makes originals cache-once, so a song's
    /// best-quality image downloads a single time and every downsampled render reuses the
    /// cached original instead of re-fetching.
    public static func configure() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 200 * 1024 * 1024 // 200 MB
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500 MB
        KingfisherManager.shared.defaultOptions = [.cacheOriginalImage, .backgroundDecode]
    }
}
#endif
