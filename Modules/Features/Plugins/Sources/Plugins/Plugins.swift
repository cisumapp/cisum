import Caching
import Foundation
import Player
import ProviderSDK
import YouTubeSDK
import Utilities

public enum Plugins {
    @MainActor private static var cachedProviderSDK: ProviderSDK?

    @MainActor
    public static func makeProviderSDK() -> ProviderSDK {
        PerfLog.info("Creating ProviderSDK instance")
        let providerSDK = ProviderSDK()
        cachedProviderSDK = providerSDK
        return providerSDK
    }

    @MainActor
    public static func sharedProviderSDK() -> ProviderSDK? {
        PerfLog.debug("Querying shared ProviderSDK available: \(String(cachedProviderSDK != nil))")
        return cachedProviderSDK
    }

    @MainActor
    public static func setSharedProviderSDK(_ providerSDK: ProviderSDK) {
        PerfLog.info("Setting shared ProviderSDK instance")
        cachedProviderSDK = providerSDK
    }

    public static func makePlaybackProviders(
        providerSDK: ProviderSDK,
        youtube: YouTube,
        mediaCacheStore: MediaCacheStore,
        metadataCache: any VideoMetadataCaching,
        includeProviderSDK: Bool = true,
        includeYouTubeFallback: Bool = true
    ) -> [any StreamResolutionProvider] {
        var providers: [any StreamResolutionProvider] = []
        PerfLog.debug("Building playback providers include_provider_sdk: \(String(includeProviderSDK)), include_youtube_fallback: \(String(includeYouTubeFallback))")

        if includeProviderSDK {
            providers.append(ProviderSDKStreamResolver(providerSDK: providerSDK, mediaCacheStore: mediaCacheStore))
        }

        if includeYouTubeFallback || providers.isEmpty {
            providers.append(
                YouTubeStreamResolver(
                    youtube: youtube,
                    mediaCacheStore: mediaCacheStore,
                    metadataCache: metadataCache
                )
            )
        }

        return providers
    }

    @MainActor private static var cachedYouTube: YouTube?
    @MainActor private static var cachedMediaCacheStore: MediaCacheStore?
    @MainActor private static var cachedMetadataCache: (any VideoMetadataCaching)?

    @MainActor
    public static func configurePlaybackURLResolver(
        providerSDK: ProviderSDK? = nil,
        youtube: YouTube,
        mediaCacheStore: MediaCacheStore,
        metadataCache: any VideoMetadataCaching,
        includeProviderSDK: Bool = true,
        includeYouTubeFallback: Bool = true
    ) {
        cachedYouTube = youtube
        cachedMediaCacheStore = mediaCacheStore
        cachedMetadataCache = metadataCache
        PerfLog.info("Configuring playback URL resolver include_provider_sdk: \(String(includeProviderSDK)), include_youtube_fallback: \(String(includeYouTubeFallback))")

        let providerSDK = providerSDK ?? cachedProviderSDK ?? ProviderSDK()
        let isReplacingProviderSDK = cachedProviderSDK !== providerSDK
        cachedProviderSDK = providerSDK

        if isReplacingProviderSDK {
            PerfLog.info("ProviderSDK selected for playback resolver source: \(providerSDK === cachedProviderSDK ? "cached" : "new")")
        }

        Task { @MainActor in
            await ProviderManifestStore.shared.reconcilePersistedManifests()
        }

        PlaybackURLResolver.configureShared(
            providers: makePlaybackProviders(
                providerSDK: providerSDK,
                youtube: youtube,
                mediaCacheStore: mediaCacheStore,
                metadataCache: metadataCache,
                includeProviderSDK: includeProviderSDK,
                includeYouTubeFallback: includeYouTubeFallback
            )
        )
    }

    @MainActor
    public static func reconfigurePlaybackURLResolver(
        includeProviderSDK: Bool,
        includeYouTubeFallback: Bool
    ) {
        guard let youtube = cachedYouTube,
              let mediaCacheStore = cachedMediaCacheStore,
              let metadataCache = cachedMetadataCache
        else {
            PerfLog.warning("Cannot reconfigure playback URL resolver because cached dependencies are missing")
            return
        }

        PerfLog.info("Reconfiguring playback URL resolver include_provider_sdk: \(String(includeProviderSDK)), include_youtube_fallback: \(String(includeYouTubeFallback))")
        configurePlaybackURLResolver(
            youtube: youtube,
            mediaCacheStore: mediaCacheStore,
            metadataCache: metadataCache,
            includeProviderSDK: includeProviderSDK,
            includeYouTubeFallback: includeYouTubeFallback
        )
    }
}
