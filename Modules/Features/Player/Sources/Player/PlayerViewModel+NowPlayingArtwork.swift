import Foundation
import MediaPlayer
import Networking
import SwiftUI
import Utilities

#if os(iOS)
import AVFoundation
import UIKit

#if canImport(iTunesKit)
import iTunesKit
#endif

#endif

@MainActor
extension PlayerViewModel {
    struct MotionArtworkSourceResolution {
        let sourceHLSURL: URL
        let videoCacheID: String
    }

    #if os(iOS)
    struct NowPlayingState: Equatable {
        var mediaID: String?
        var title: String = "Not Playing"
        var artist: String = ""
        var artworkURL: URL?
        var duration: Double = 0
        var elapsedTime: Double = 0
        var playbackRate: Float = 0
    }

    struct CachedNowPlayingArtworkResource {
        let url: URL
        let data: Data
        let size: CGSize
    }

    func updateNowPlayingMetadata(force: Bool = true) {
        nowPlayingState.mediaID = currentVideoId
        nowPlayingState.title = currentTitle
        nowPlayingState.artist = currentArtist
        nowPlayingState.artworkURL = currentImageURL
        updateNowPlayingPlaybackInfo(force: force)
    }

    func updateNowPlayingPlaybackInfo(force: Bool = false) {
        nowPlayingState.elapsedTime = currentElapsedTimeSnapshot()
        nowPlayingState.duration = currentDurationSnapshot()
        nowPlayingState.playbackRate = currentPlaybackRateSnapshot()

        publishNowPlayingInfo(force: force)
    }

    func loadNowPlayingArtwork(for mediaID: String, title: String, artist: String, fallbackURL: URL?) {
        artworkLoadTask?.cancel()

        let artworkTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let artworkArtist = normalizedMusicDisplayArtist(artist, title: title)
        let fallbackArtworkURL = fallbackURL

        artworkLoadTask = Task { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            // 1. Persistent cache — instant hit, no network
            if let persistedArtwork = await loadPersistentArtworkIfAvailable(for: mediaID) {
                guard currentVideoId == mediaID, !Task.isCancelled else { return }
                applyArtwork(persistedArtwork, for: mediaID, cacheInMemory: true)
                updateNowPlayingMetadata(force: true)
                return
            }

            // 2. Resolve the best artwork URL from all available sources
            guard let bestURL = await resolveBestArtworkURL(
                mediaID: mediaID,
                title: artworkTitle,
                artist: artworkArtist,
                fallbackURL: fallbackArtworkURL
            ) else { return }
            guard currentVideoId == mediaID, !Task.isCancelled else { return }

            // 3. Download the best artwork
            guard let artwork = await Self.fetchArtworkResource(from: bestURL) else {
                if bestURL != fallbackArtworkURL {
                    guard let fallbackArtwork = await Self.fetchArtworkResource(from: fallbackArtworkURL) else { return }
                    guard currentVideoId == mediaID, !Task.isCancelled else { return }
                    applyArtwork(fallbackArtwork, for: mediaID, cacheInMemory: false)
                    updateNowPlayingMetadata(force: true)
                }
                return
            }
            guard currentVideoId == mediaID, !Task.isCancelled else { return }

            // 4. Apply once — no visual swap from fallback-to-high-quality
            applyArtwork(artwork, for: mediaID, cacheInMemory: true)
            updateNowPlayingMetadata(force: true)
            await persistArtwork(artwork, mediaID: mediaID)
        }
    }

    private func resolveBestArtworkURL(
        mediaID: String,
        title: String,
        artist: String,
        fallbackURL: URL?
    ) async -> URL? {
        if let cachedURL = await mediaCacheStore.cachedHighQualityArtworkURL(
            for: mediaID,
            maxAge: CachePolicy.highQualityArtworkTTL
        ) {
            return cachedURL
        }

        if let payloadURL = externalPayloadCache[mediaID]?.artworkURL {
            return payloadURL
        }

        #if canImport(iTunesKit)
        if let itunesURL = await Self.resolveHighQualityArtworkURL(
            using: itunes,
            title: title,
            artist: artist
        ) {
            await mediaCacheStore.saveHighQualityArtworkURL(itunesURL, for: mediaID)
            return itunesURL
        }
        #endif

        return fallbackURL
    }

    private func currentElapsedTimeSnapshot() -> Double {
        max(currentTime, 0)
    }

    private func currentDurationSnapshot() -> Double {
        guard duration.isFinite, !duration.isNaN else {
            return 0
        }

        return max(duration, 0)
    }

    private func currentPlaybackRateSnapshot() -> Float {
        isPlaying ? max(player.rate, 1) : 0
    }

    private func publishNowPlayingInfo(force: Bool) {
        if !force, let lastPublishedNowPlayingState {
            let elapsedChangedEnough = abs(lastPublishedNowPlayingState.elapsedTime - nowPlayingState.elapsedTime) >= 0.5
            let metadataChanged = lastPublishedNowPlayingState.mediaID != nowPlayingState.mediaID
                || lastPublishedNowPlayingState.title != nowPlayingState.title
                || lastPublishedNowPlayingState.artist != nowPlayingState.artist
                || lastPublishedNowPlayingState.artworkURL != nowPlayingState.artworkURL
                || abs(lastPublishedNowPlayingState.duration - nowPlayingState.duration) >= 0.001
                || abs(Double(lastPublishedNowPlayingState.playbackRate - nowPlayingState.playbackRate)) >= 0.001

            guard elapsedChangedEnough || metadataChanged else {
                return
            }
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = nowPlayingState.title
        info[MPMediaItemPropertyArtist] = nowPlayingState.artist
        info[MPMediaItemPropertyPlaybackDuration] = nowPlayingState.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nowPlayingState.elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = nowPlayingState.playbackRate

        if let currentArtworkResource,
           let mediaItemArtwork = Self.makeMediaItemArtwork(from: currentArtworkResource) {
            info[MPMediaItemPropertyArtwork] = mediaItemArtwork
        }

        if #available(iOS 26.0, *) {
            let tallArtworkKey = "MPNowPlayingInfoProperty3x4AnimatedArtwork"

            if let videoURL = animatedArtworkVideoURL {
                let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
                let artworkID = nowPlayingState.mediaID ?? UUID().uuidString

                if supportedKeys.contains(tallArtworkKey) {
                    let tallArtwork = Self.makeAnimatedArtwork(
                        mediaID: artworkID,
                        videoURL: videoURL,
                        previewData: currentArtworkResource?.data
                    )
                    info[tallArtworkKey] = tallArtwork
                } else {
                    info[tallArtworkKey] = nil
                }
            } else {
                info[tallArtworkKey] = nil
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        #if os(macOS)
        if #available(macOS 10.12.2, *) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
        #endif

        lastPublishedNowPlayingState = nowPlayingState
    }

    func applyCachedArtworkIfAvailable(for mediaID: String) {
        guard let cachedArtwork = artworkCache[mediaID] else {
            currentArtworkResource = nil
            currentArtworkMediaID = nil
            return
        }

        cacheAccessOrder[mediaID] = Date()
        applyArtwork(cachedArtwork, for: mediaID, cacheInMemory: false)
    }

    private func applyArtwork(
        _ artwork: CachedNowPlayingArtworkResource,
        for mediaID: String,
        cacheInMemory: Bool
    ) {
        currentImageURL = artwork.url
        currentArtworkResource = artwork
        currentArtworkMediaID = mediaID
        updateAccentColor(from: artwork, mediaID: mediaID)

        if cacheInMemory {
            artworkCache[mediaID] = artwork
            if artworkCache.count > 50 {
                let sorted = artworkCache.keys.sorted { lhs, rhs in
                    (cacheAccessOrder[lhs] ?? Date.distantPast) < (cacheAccessOrder[rhs] ?? Date.distantPast)
                }
                let overage = sorted.prefix(artworkCache.count - 50)
                for key in overage {
                    artworkCache.removeValue(forKey: key)
                    cacheAccessOrder.removeValue(forKey: key)
                }
            }
            cacheAccessOrder[mediaID] = Date()
        }
    }

    private func updateAccentColor(from artwork: CachedNowPlayingArtworkResource, mediaID: String) {
        if let cachedAccent = artworkAccentCache[mediaID],
           cachedAccent.artworkURL == artwork.url {
            applyCurrentAccentColor(cachedAccent.color)
            return
        }

        accentLoadTask?.cancel()
        let artworkData = artwork.data
        let artworkURL = artwork.url

        accentLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let extractedPalette = await artworkColorExtractor.extractPalette(from: artworkData, cacheKey: artworkURL.absoluteString)

            guard !Task.isCancelled else { return }
            guard currentVideoId == mediaID else { return }

            artworkPaletteCache[mediaID] = (artworkURL: artworkURL, palette: extractedPalette)
            let currentAccentColor = extractedPalette?.dominant ?? .cisumAccent
            artworkAccentCache[mediaID] = (artworkURL: artworkURL, color: currentAccentColor)
            applyCurrentAccentColor(currentAccentColor)
        }
    }

    private func applyCurrentAccentColor(_ color: Color) {
        currentAccentColor = color
        Color.updateDynamicAccent(color)
    }

    private func loadPersistentArtworkIfAvailable(for mediaID: String) async -> CachedNowPlayingArtworkResource? {
        guard let cachedArtwork = await mediaCacheStore.cachedLocalArtworkData(for: mediaID),
              let image = UIImage(data: cachedArtwork.data)
        else {
            return nil
        }

        return CachedNowPlayingArtworkResource(
            url: cachedArtwork.url,
            data: cachedArtwork.data,
            size: image.size
        )
    }

    private func persistArtwork(_ artwork: CachedNowPlayingArtworkResource, mediaID: String) async {
        _ = await mediaCacheStore.saveArtworkData(
            artwork.data,
            mediaID: mediaID,
            sourceURL: artwork.url
        )
    }

    #if canImport(iTunesKit)
    private nonisolated static func resolveHighQualityArtworkURL(using itunes: iTunesKit, title: String, artist: String) async -> URL? {
        do {
            let searchTitle = normalizedMusicDisplayTitle(title, artist: artist)
            let searchArtist = normalizedMusicDisplayArtist(artist, title: title)
            let response = try await itunes.search(term: "\(searchTitle) \(searchArtist)", country: "us", media: "music", limit: 1)
            return normalizedITunesArtworkURL(from: response.results.first?.artworkUrl100)
        } catch {
            return nil
        }
    }
    #endif

    func resolveMotionArtworkSource(
        for mediaID: String,
        title: String,
        artist: String,
        albumName: String?
    ) async -> MotionArtworkSourceResolution? {
        let searchTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let searchArtist = normalizedMusicDisplayArtist(artist, title: title)
        let localAlbumArtistCacheKey = normalizedMotionArtworkAlbumCacheKey(
            albumName: albumName,
            artistName: searchArtist
        )
        let localAlbumOnlyCacheKey = normalizedMotionArtworkAlbumCacheKey(
            albumName: albumName,
            artistName: nil as String?
        )
        let localAlbumCacheKeys = [localAlbumArtistCacheKey, localAlbumOnlyCacheKey].compactMap(\.self)

        if let cachedURL = await mediaCacheStore.cachedMotionArtworkSourceURL(
            for: mediaID,
            maxAge: CachePolicy.motionArtworkSourceTTL
        ) {
            logAnimatedArtwork("Motion artwork source cache hit (media) for id=\(mediaID)")
            return MotionArtworkSourceResolution(
                sourceHLSURL: cachedURL,
                videoCacheID: motionArtworkVideoCacheID(
                    mediaID: mediaID,
                    albumCacheKey: localAlbumArtistCacheKey ?? localAlbumOnlyCacheKey,
                    sourceURL: cachedURL
                )
            )
        }

        if let albumHit = await mediaCacheStore.cachedMotionArtworkSourceURL(
            forAlbumKeys: localAlbumCacheKeys,
            maxAge: CachePolicy.motionArtworkSourceTTL
        ) {
            logAnimatedArtwork("Motion artwork source cache hit (album key=\(albumHit.albumKey)) for id=\(mediaID)")
            await mediaCacheStore.saveMotionArtworkSourceURL(albumHit.url, for: mediaID)
            return MotionArtworkSourceResolution(
                sourceHLSURL: albumHit.url,
                videoCacheID: motionArtworkVideoCacheID(
                    mediaID: mediaID,
                    albumCacheKey: albumHit.albumKey,
                    sourceURL: albumHit.url
                )
            )
        }

        #if canImport(iTunesKit)
        guard let resolution = await Self.resolveMotionArtwork(
            using: itunes,
            title: searchTitle,
            artist: searchArtist
        ) else {
            return nil
        }
        #else
        return nil
        #endif

        await mediaCacheStore.saveMotionArtworkSourceURL(resolution.sourceURL, for: mediaID)

        var albumKeysToPersist = localAlbumCacheKeys
        let collectionCacheKey = motionArtworkCollectionCacheKey(collectionID: resolution.collectionID)
        if let collectionCacheKey {
            albumKeysToPersist.append(collectionCacheKey)
        }
        let catalogAlbumCacheKey = motionArtworkCatalogAlbumCacheKey(catalogAlbumID: resolution.catalogAlbumID)
        if let catalogAlbumCacheKey {
            albumKeysToPersist.append(catalogAlbumCacheKey)
        }
        await mediaCacheStore.saveMotionArtworkSourceURL(resolution.sourceURL, forAlbumKeys: albumKeysToPersist)

        let selectedAlbumKey = catalogAlbumCacheKey
            ?? collectionCacheKey
            ?? localAlbumArtistCacheKey
            ?? localAlbumOnlyCacheKey
        logAnimatedArtwork(
            "Motion artwork source fetched from iTunes for id=\(mediaID) collection=\(resolution.collectionID.map(String.init) ?? "none")"
        )
        return MotionArtworkSourceResolution(
            sourceHLSURL: resolution.sourceURL,
            videoCacheID: motionArtworkVideoCacheID(
                mediaID: mediaID,
                albumCacheKey: selectedAlbumKey,
                sourceURL: resolution.sourceURL
            )
        )
    }

    #if canImport(iTunesKit)
    private nonisolated static func resolveMotionArtwork(
        using itunes: iTunesKit,
        title: String,
        artist: String
    ) async -> iTunesMotionArtworkResolution? {
        do {
            return try await itunes.resolveMotionArtwork(
                term: "\(title) \(artist)",
                country: "us"
            )
        } catch {
            return nil
        }
    }
    #endif

    private nonisolated static func fetchArtworkResource(from url: URL?) async -> CachedNowPlayingArtworkResource? {
        guard let url else { return nil }

        do {
            let data = try await NetworkingClient.shared.downloadData(url: url)
            guard let image = UIImage(data: data) else { return nil }
            return CachedNowPlayingArtworkResource(url: url, data: data, size: image.size)
        } catch {
            return nil
        }
    }

    private nonisolated static func makeMediaItemArtwork(from resource: CachedNowPlayingArtworkResource) -> MPMediaItemArtwork? {
        let imageData = resource.data
        let boundsSize = resource.size

        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            UIImage(data: imageData) ?? UIImage()
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func makeAnimatedArtwork(
        mediaID: String,
        videoURL: URL,
        previewData: Data?
    ) -> MPMediaItemAnimatedArtwork? {
        guard videoURL.isFileURL else {
            return nil
        }

        let artworkID = "\(mediaID)-\(videoURL.lastPathComponent)"
        return MPMediaItemAnimatedArtwork(
            artworkID: artworkID,
            previewImageRequestHandler: { requestedSize in
                guard let previewData,
                      let image = UIImage(data: previewData)
                else {
                    return nil
                }

                return makeAnimatedArtworkPreviewImage(
                    from: image,
                    requestedSize: requestedSize
                )
            },
            videoAssetFileURLRequestHandler: { _ in
                videoURL
            }
        )
    }

    @available(iOS 26.0, *)
    private nonisolated static func makeAnimatedArtworkPreviewImage(
        from image: UIImage,
        requestedSize: CGSize
    ) -> UIImage {
        let targetSize = normalizedAnimatedArtworkPreviewSize(
            requestedSize,
            fallbackSize: image.size
        )

        guard targetSize.width > 0,
              targetSize.height > 0,
              image.size.width > 0,
              image.size.height > 0
        else {
            return image
        }

        let sourceAspectRatio = image.size.width / image.size.height
        let targetAspectRatio = targetSize.width / targetSize.height

        let drawRect: CGRect
        if sourceAspectRatio > targetAspectRatio {
            let scaledHeight = targetSize.height
            let scaledWidth = scaledHeight * sourceAspectRatio
            drawRect = CGRect(
                x: (targetSize.width - scaledWidth) / 2,
                y: 0,
                width: scaledWidth,
                height: scaledHeight
            )
        } else {
            let scaledWidth = targetSize.width
            let scaledHeight = scaledWidth / sourceAspectRatio
            drawRect = CGRect(
                x: 0,
                y: (targetSize.height - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale > 0 ? image.scale : 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: drawRect)
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func normalizedAnimatedArtworkPreviewSize(
        _ requestedSize: CGSize,
        fallbackSize: CGSize
    ) -> CGSize {
        if requestedSize.width > 0,
           requestedSize.height > 0,
           requestedSize.width.isFinite,
           requestedSize.height.isFinite {
            return requestedSize
        }

        if fallbackSize.width > 0,
           fallbackSize.height > 0,
           fallbackSize.width.isFinite,
           fallbackSize.height.isFinite {
            return fallbackSize
        }

        return CGSize(width: 512, height: 512)
    }
    #else
    func updateNowPlayingMetadata(force _: Bool = true) {}
    func updateNowPlayingPlaybackInfo(force _: Bool = false) {}
    func loadNowPlayingArtwork(for _: String, title _: String, artist _: String, fallbackURL _: URL?) {}
    func resolveMotionArtworkSource(
        for mediaID: String,
        title: String,
        artist: String,
        albumName: String?
    ) async -> MotionArtworkSourceResolution? {
        _ = mediaID
        _ = title
        _ = artist
        _ = albumName
        return nil
    }
    #endif
}
