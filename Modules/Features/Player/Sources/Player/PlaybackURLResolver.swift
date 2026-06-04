import Foundation
import Models
import os
import ProviderSDK
import Utilities
import YouTubeSDK

// Aliased for clarity at call sites inside this file.
private let resolverLog = CisumLog.resolver
private let resolverSP = CisumSignpost.resolver

/// Lightweight actor to pre-resolve and cache playable stream URLs (HLS preferred)
/// so UI components (Search / Player) can obtain a quick URL to start playback
/// while the full metadata resolution continues in the background.
///
/// ## Resolution strategy
/// All registered `StreamResolutionProvider` implementations are raced concurrently.
/// Every candidate from every provider is collected, then sorted by quality score so
/// the highest-quality stream (e.g. a TIDAL FLAC) always wins over a YouTube AAC
/// fallback — even when both providers respond at roughly the same time.
public actor PlaybackURLResolver {
    @MainActor private static var _shared: PlaybackURLResolver?

    public static func sharedInstance() async -> PlaybackURLResolver {
        await MainActor.run {
            if let s = _shared { return s }
            let resolver = PlaybackURLResolver(providers: [])
            _shared = resolver
            return resolver
        }
    }

    @MainActor
    public static func configureShared(providers: [StreamResolutionProvider]) {
        _shared = PlaybackURLResolver(providers: providers)
    }

    private let providers: [StreamResolutionProvider]

    public init(providers: [StreamResolutionProvider]) {
        self.providers = providers
    }

    public func cachedURL(for videoID: String) async -> URL? {
        for provider in providers {
            if let url = await provider.cachedURL(for: videoID) {
                resolverLog.debug("Cached URL hit via \(self.resolverLabel(for: provider), privacy: .public) for \(videoID, privacy: .public)")
                return url
            }
        }
        return nil
    }

    /// Prewarm playback info for a list of video IDs. This fetches minimal data and caches
    /// the best candidate URL for quick startup (HLS preferred).
    /// Uses bounded concurrency (max 2) to avoid flooding YouTube with player requests.
    public func prewarm(_ ids: [String], title: String = "", artist: String = "", duration: TimeInterval? = nil) async {
        guard !ids.isEmpty else { return }

        let spid = resolverSP.begin("prewarm", "count=\(ids.count)")
        defer { resolverSP.end("prewarm", state: spid, "count=\(ids.count)") }

        await withThrowingTaskGroup(of: Void.self) { group in
            var submitted = 0
            let maxConcurrent = 2
            for id in ids {
                if submitted >= maxConcurrent {
                    try? await group.next()
                    submitted -= 1
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = try? await resolve(mediaID: id, title: title, artist: artist, duration: duration)
                }
                submitted += 1
            }
        }
    }

    /// Resolves a playable stream for `mediaID` by racing all registered providers
    /// concurrently and returning the candidates sorted highest-quality first.
    ///
    /// If only one provider succeeds the result is returned immediately without
    /// waiting for the others. If multiple providers succeed their candidates are
    /// merged and ranked so the caller always receives the best stream at index 0.
    public func resolve(
        mediaID: String,
        title: String,
        artist: String,
        representations: [TrackRepresentation]? = nil,
        forceDecipher: Bool = false,
        duration: TimeInterval? = nil
    ) async throws -> [PlaybackCandidate] {
        let resolveSpid = resolverSP.begin("resolve", "id=\(mediaID) forceDecipher=\(forceDecipher)")
        let startTime = Date()
        defer {
            resolverSP.end("resolve", state: resolveSpid, "id=\(mediaID)")
            let duration = Date().timeIntervalSince(startTime)
            resolverLog.notice("⏱️ STREAM RESOLUTION TOOK \(String(format: "%.3f", duration))s for \(mediaID, privacy: .public)")
        }

        // 1. Fast cache path — check all providers' in-memory caches first.
        if !forceDecipher {
            if let cached = await cachedURL(for: mediaID) {
                let streamKind: PlaybackCandidate.StreamKind = cached.pathExtension.lowercased() == "m3u8" ? .hls : .muxed
                resolverLog.debug("Cache hit for \(mediaID, privacy: .public)")
                resolverSP.event("cache-hit", "id=\(mediaID)")
                return [PlaybackCandidate(url: cached, streamKind: streamKind, mimeType: nil, itag: nil, expiresAt: Date().addingTimeInterval(3600), isCompatible: true)]
            }
        }

        guard !providers.isEmpty else {
            throw ResolverError.resolutionFailed(mediaID: mediaID)
        }

        // 2. Race all providers concurrently — collect every candidate from every provider.
        //    Using a structured task group ensures cancellation propagates correctly.
        //
        //    Optimization: when all representations are YouTube-only (youtube, youtubeMusic),
        //    skip ProviderSDK entirely — it can never resolve YouTube content and the failed
        //    federated search wastes ~100ms.
        let ytProviders = ["youtube", "youtubemusic", "youtube_music", "youtubeMusic"]
        let isYouTubeOnly = {
            guard let reps = representations, !reps.isEmpty else { return false }
            return reps.allSatisfy { ytProviders.contains($0.providerID.lowercased()) }
        }()
        let activeProviders = isYouTubeOnly
            ? providers.filter { $0 is YouTubeStreamResolver }
            : providers
        var allCandidates: [PlaybackCandidate] = []
        var lastError: Error?

        let raceSpid = resolverSP.begin("provider-race", "id=\(mediaID) providers=\(activeProviders.count)")
        await withTaskGroup(of: (String, Result<[PlaybackCandidate], Error>).self) { group in
            for provider in activeProviders {
                let label = resolverLabel(for: provider)
                group.addTask {
                    guard !Task.isCancelled else {
                        return (label, .failure(CancellationError()))
                    }
                    do {
                        let candidates = try await provider.resolveStream(
                            mediaID: mediaID,
                            title: title,
                            artist: artist,
                            representations: representations,
                            forceDecipher: forceDecipher,
                            duration: duration
                        )
                        return (label, .success(candidates))
                    } catch {
                        return (label, .failure(error))
                    }
                }
            }

            for await (label, result) in group {
                switch result {
                case let .success(candidates) where !candidates.isEmpty:
                    resolverLog.info("\(label, privacy: .public) resolved \(candidates.count) candidate(s) for \(mediaID, privacy: .public) — top MIME: \(candidates.first?.mimeType ?? "unknown", privacy: .public)")
                    resolverSP.event("provider-success", "provider=\(label) id=\(mediaID) count=\(candidates.count)")
                    allCandidates.append(contentsOf: candidates)
                case let .failure(error) where !(error is CancellationError):
                    lastError = error
                    resolverLog.warning("\(label, privacy: .public) failed for \(mediaID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    resolverSP.event("provider-failure", "provider=\(label) id=\(mediaID)")
                default:
                    break
                }
            }
        }
        resolverSP.end("provider-race", state: raceSpid, "id=\(mediaID) candidates=\(allCandidates.count)")

        if allCandidates.isEmpty {
            throw lastError ?? ResolverError.resolutionFailed(mediaID: mediaID)
        }

        // 3. Sort candidates by quality score (highest first) so the caller always
        //    finds the best stream at index 0.
        let ranked = allCandidates
            .filter(\.isCompatible)
            .sorted { qualityScore(for: $0) > qualityScore(for: $1) }

        // Log a downgrade warning when we had to fall back from hi-res to lossy.
        if allCandidates.contains(where: \.isCompatible) {
            let topMime = ranked.first?.mimeType ?? "unknown"
            let topScore = ranked.first.map { qualityScore(for: $0) } ?? 0
            if topScore < 50 {
                resolverLog.warning("Quality downgrade for \(mediaID, privacy: .public): no hi-res/lossless candidate found, serving \(topMime, privacy: .public)")
            }
        }

        // If all candidates are incompatible fall back to the unfiltered set.
        return ranked.isEmpty ? allCandidates : ranked
    }

    // MARK: - Quality Ranking

    /// Returns a numeric quality score for a `PlaybackCandidate` based on its MIME
    /// type string. Higher scores indicate a better listening experience.
    ///
    /// Score ranges:
    /// - 90–100: Lossless / Hi-Res (FLAC, ALAC, DSD)
    /// - 60–79:  High-quality lossy (AAC 256+, Opus)
    /// - 40–59:  Standard lossy (AAC, MP3 128+, HLS adaptive)
    /// - 20–39:  Low quality / muxed video container
    private func qualityScore(for candidate: PlaybackCandidate) -> Int {
        let mime = (candidate.mimeType ?? "").lowercased()

        if mime.contains("flac") || mime.contains("alac") || mime.contains("dsd") {
            return 100 // True lossless
        }
        if mime.contains("ogg") && mime.contains("opus") {
            return 72 // Opus (transparent at 128+ kbps)
        }
        if mime.contains("aac") {
            // Prefer higher-bitrate AAC when the resolver encoded it in the MIME string
            if mime.contains("bitrate="),
               let bitrateStr = mime.split(separator: "=").last.flatMap({ Int($0) })
            {
                return 50 + min(bitrateStr / 10, 28) // 50–78 range
            }
            return 60
        }
        if mime.contains("x-mpegurl") || mime.contains("vnd.apple.mpegurl") {
            return 55 // HLS adaptive — good but quality varies
        }
        if mime.contains("mpeg") || mime.contains("mp3") {
            // Prefer higher-bitrate MP3 when encoded in the MIME string
            if mime.contains("bitrate="),
               let bitrateStr = mime.split(separator: "=").last.flatMap({ Int($0) })
            {
                return 30 + min(bitrateStr / 10, 18) // 30–48 range
            }
            return 40
        }
        if mime.contains("mp4") {
            return 25 // Muxed video container — last resort
        }

        return 20 // Unknown — treat as lowest priority
    }

    enum ResolverError: Error {
        case resolutionFailed(mediaID: String)
    }

    private func resolverLabel(for provider: StreamResolutionProvider) -> String {
        switch provider {
        case is ProviderSDKStreamResolver:
            "ProviderSDK"
        case is YouTubeStreamResolver:
            "YouTube"
        default:
            String(describing: type(of: provider))
        }
    }
}
