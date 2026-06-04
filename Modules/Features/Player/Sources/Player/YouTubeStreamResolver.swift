import Caching
import Foundation
import Models
import os
import ProviderSDK
import Utilities
import YouTubeSDK

private let resolverLog = CisumLog.resolver
private let resolverSP = CisumSignpost.resolver

public struct YouTubeStreamResolver: StreamResolutionProvider {
    private let youtube: YouTube
    private let mediaCacheStore: MediaCacheStore
    private let metadataCache: any VideoMetadataCaching

    public init(
        youtube: YouTube,
        mediaCacheStore: MediaCacheStore,
        metadataCache: any VideoMetadataCaching
    ) {
        self.youtube = youtube
        self.mediaCacheStore = mediaCacheStore
        self.metadataCache = metadataCache
    }

    public func resolveStream(
        mediaID: String,
        title: String,
        artist: String,
        representations: [TrackRepresentation]?,
        forceDecipher: Bool,
        duration: TimeInterval? = nil
    ) async throws -> [PlaybackCandidate] {
        try await resolveStream(mediaID: mediaID, title: title, artist: artist, representations: representations, forceDecipher: forceDecipher, duration: duration, depth: 0)
    }

    private func resolveStream(
        mediaID: String,
        title: String,
        artist: String,
        representations: [TrackRepresentation]?,
        forceDecipher _: Bool,
        duration: TimeInterval?,
        depth: Int
    ) async throws -> [PlaybackCandidate] {
        let spid = resolverSP.begin("yt-resolve", "id=\(mediaID)")
        defer { resolverSP.end("yt-resolve", state: spid, "id=\(mediaID)") }

        let normalizedMediaID = canonicalPlaybackMediaID(mediaID)

        // Extract the real YouTube video ID from representations if available.
        let youtubeVideoID: String = {
            let ytProviders = ["youtube", "youtubemusic", "youtube_music", "youtubeMusic"]
            if let rep = representations?.first(where: { ytProviders.contains($0.providerID.lowercased()) }),
               rep.providerTrackID.count == 11
            {
                return rep.providerTrackID
            }
            return normalizedMediaID
        }()

        let isValidYTID: Bool = {
            guard youtubeVideoID.count == 11 else { return false }
            let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            return youtubeVideoID.unicodeScalars.allSatisfy { validChars.contains($0) }
        }()

        resolverLog.notice("--- Resolving \(youtubeVideoID, privacy: .public) title=\(title, privacy: .public) artist=\(artist, privacy: .public) ---")

        let startTime = Date()

        // Phase 1: Run SDK-Direct + both searches in parallel.
        // Search tasks return candidate video IDs (fast, ~1-2s).
        // SDK-Direct returns full candidates (slower, ~4-10s).
        struct SearchResult {
            let videoId: String
            let title: String
            let artist: String
            let score: Double
            let duration: TimeInterval?
            let source: String
        }

        let result: [PlaybackCandidate] = await withTaskGroup(of: [PlaybackCandidate]?.self, returning: [PlaybackCandidate].self) { group in
            // When we already have a valid YouTube ID, SDK-Direct always wins.
            // Skip both search phases to save 1-3s on first play.
            let shouldSkipSearch = isValidYTID && depth == 0
            if shouldSkipSearch {
                resolverLog.debug("Skipping search — valid YouTube ID, going straight to SDK-Direct")
            }

            // Method 1: SDK Direct resolve (if we have a valid YouTube ID)
            if isValidYTID {
                group.addTask {
                    let methodStart = Date()
                    resolverLog.debug("Race [SDK-Direct] starting for \(youtubeVideoID, privacy: .public)")
                    let raceSpid = resolverSP.begin("race-sdk-direct", "id=\(youtubeVideoID)")
                    defer { resolverSP.end("race-sdk-direct", state: raceSpid, "id=\(youtubeVideoID)") }

                    do {
                        let info = try await YouTubeSDK.YouTubeStreamResolver.shared.resolve(
                            videoId: youtubeVideoID,
                            preferAudio: false,
                            api: nil
                        )
                        var candidates: [PlaybackCandidate] = []
                        if let hls = info.hlsURL {
                            candidates.append(PlaybackCandidate(
                                url: hls,
                                headers: ["User-Agent": InnerTubeClients.WebSafari.userAgent],
                                streamKind: .hls,
                                mimeType: "application/x-mpegURL",
                                itag: nil,
                                expiresAt: Date().addingTimeInterval(3600 * 4),
                                isCompatible: true
                            ))
                        }
                        if let muxed = info.bestMuxedDownloadURL {
                            candidates.append(PlaybackCandidate(
                                url: muxed,
                                headers: ["User-Agent": InnerTubeClients.Android.userAgent],
                                streamKind: .muxed,
                                mimeType: "video/mp4",
                                itag: nil,
                                expiresAt: Date().addingTimeInterval(3600 * 4),
                                isCompatible: true
                            ))
                        }
                        let elapsed = Date().timeIntervalSince(methodStart)
                        if !candidates.isEmpty {
                            resolverLog.notice("Race [SDK-Direct] ✅ WINNER — \(candidates.count) candidates in \(String(format: "%.2f", elapsed))s")
                            return candidates
                        }
                        resolverLog.debug("Race [SDK-Direct] no candidates in \(String(format: "%.2f", elapsed))s")
                    } catch {
                        let elapsed = Date().timeIntervalSince(methodStart)
                        resolverLog.debug("Race [SDK-Direct] failed in \(String(format: "%.2f", elapsed))s: \(error.localizedDescription, privacy: .public)")
                    }
                    return nil
                }
            }

            // Method 2: YouTube Music search → return best candidate (search only, no resolve yet)
            if !shouldSkipSearch, !title.isEmpty, !artist.isEmpty, depth < 1 {
                group.addTask {
                    let methodStart = Date()
                    resolverLog.debug("Race [Music-Search] starting for '\(title, privacy: .public) \(artist, privacy: .public)'")
                    let raceSpid = resolverSP.begin("race-music-search", "query=\(title) \(artist)")
                    defer { resolverSP.end("race-music-search", state: raceSpid, "query=\(title) \(artist)") }

                    do {
                        let query = "\(title) \(artist)"
                        let searchResults = try await youtube.music.search(query)
                        if let bestResult = pickBestSearchResult(
                            from: searchResults.map { SearchCandidate(
                                videoId: $0.videoId,
                                title: $0.title,
                                artist: $0.artistsDisplay,
                                duration: $0.duration
                            ) },
                            sourceTitle: title,
                            sourceArtist: artist,
                            sourceDuration: duration
                        ) {
                            let elapsed = Date().timeIntervalSince(methodStart)
                            resolverLog.debug("Race [Music-Search] found '\(bestResult.title, privacy: .public)' (score=\(bestResult.score, privacy: .public)) in \(String(format: "%.2f", elapsed))s")
                            // Return nil here — we'll resolve deduplicated IDs in Phase 2
                            return nil
                        }
                    } catch {
                        let elapsed = Date().timeIntervalSince(methodStart)
                        resolverLog.debug("Race [Music-Search] failed in \(String(format: "%.2f", elapsed))s: \(error.localizedDescription, privacy: .public)")
                    }
                    return nil
                }
            }

            // Method 3: YouTube (non-Music) search → return best candidate (search only, no resolve yet)
            if !shouldSkipSearch, !title.isEmpty, !artist.isEmpty, depth < 1 {
                group.addTask {
                    let methodStart = Date()
                    resolverLog.debug("Race [YT-Search] starting for '\(title, privacy: .public) \(artist, privacy: .public)'")
                    let raceSpid = resolverSP.begin("race-yt-search", "query=\(title) \(artist)")
                    defer { resolverSP.end("race-yt-search", state: raceSpid, "query=\(title) \(artist)") }

                    do {
                        let query = "\(title) \(artist)"
                        let api = await YouTubeSDK.YouTubeStreamResolver.shared.api
                        let searchResult = try await api.search(query: query, filter: SearchFilter(type: .video))
                        let searchCandidates = searchResult.videos
                            .filter { $0.id.count == 11 }
                            .map { SearchCandidate(
                                videoId: $0.id,
                                title: $0.title,
                                artist: $0.channelTitle,
                                duration: $0.duration
                            ) }
                        if let bestResult = pickBestSearchResult(
                            from: searchCandidates,
                            sourceTitle: title,
                            sourceArtist: artist,
                            sourceDuration: duration
                        ) {
                            let elapsed = Date().timeIntervalSince(methodStart)
                            resolverLog.debug("Race [YT-Search] found '\(bestResult.title, privacy: .public)' (score=\(bestResult.score, privacy: .public)) in \(String(format: "%.2f", elapsed))s")
                            // Return nil here — we'll resolve deduplicated IDs in Phase 2
                            return nil
                        }
                    } catch {
                        let elapsed = Date().timeIntervalSince(methodStart)
                        resolverLog.debug("Race [YT-Search] failed in \(String(format: "%.2f", elapsed))s: \(error.localizedDescription, privacy: .public)")
                    }
                    return nil
                }
            }

            // Collect first non-nil result, cancel remaining tasks
            for await result in group {
                if let candidates = result, !candidates.isEmpty {
                    group.cancelAll()
                    return candidates
                }
            }
            return []
        }

        // If SDK-Direct already succeeded, return immediately
        if !result.isEmpty {
            let totalElapsed = Date().timeIntervalSince(startTime)
            resolverLog.notice("⏱️ STREAM RESOLUTION TOOK \(String(format: "%.2f", totalElapsed))s for \(normalizedMediaID, privacy: .public)")
            await mediaCacheStore.savePlaybackResolution(mediaID: normalizedMediaID, candidates: result, validUntil: nil)
            return result
        }

        // Phase 2: Both searches ran but their results were discarded (nil returns).
        // Re-run searches to get video IDs, deduplicate, then resolve unique IDs in parallel.
        if !title.isEmpty, !artist.isEmpty, depth < 1 {
            var seenVideoIDs: Set<String> = []
            var searchCandidates: [(videoId: String, title: String, artist: String, score: Double, duration: TimeInterval?, source: String)] = []

            // Run both searches in parallel to collect candidates.
            // Each task returns its result instead of mutating shared state.
            let searchResults: [(videoId: String, title: String, artist: String, score: Double, duration: TimeInterval?, source: String)?] = await withTaskGroup(
                of: (videoId: String, title: String, artist: String, score: Double, duration: TimeInterval?, source: String)?.self
            ) { group in
                group.addTask {
                    do {
                        let query = "\(title) \(artist)"
                        let searchResults = try await youtube.music.search(query)
                        if let best = pickBestSearchResult(
                            from: searchResults.map { SearchCandidate(videoId: $0.videoId, title: $0.title, artist: $0.artistsDisplay, duration: $0.duration) },
                            sourceTitle: title, sourceArtist: artist, sourceDuration: duration
                        ) {
                            return (best.videoId, best.title, best.artist, best.score, best.duration, "Music-Search")
                        }
                    } catch {}
                    return nil
                }
                group.addTask {
                    do {
                        let query = "\(title) \(artist)"
                        let api = await YouTubeSDK.YouTubeStreamResolver.shared.api
                        let searchResult = try await api.search(query: query, filter: SearchFilter(type: .video))
                        let candidates = searchResult.videos
                            .filter { $0.id.count == 11 }
                            .map { SearchCandidate(videoId: $0.id, title: $0.title, artist: $0.channelTitle, duration: $0.duration) }
                        if let best = pickBestSearchResult(
                            from: candidates,
                            sourceTitle: title, sourceArtist: artist, sourceDuration: duration
                        ) {
                            return (best.videoId, best.title, best.artist, best.score, best.duration, "YT-Search")
                        }
                    } catch {}
                    return nil
                }
                var collected: [(videoId: String, title: String, artist: String, score: Double, duration: TimeInterval?, source: String)?] = []
                for await r in group {
                    collected.append(r)
                }
                return collected
            }
            searchCandidates = searchResults.compactMap(\.self)

            // Deduplicate by video ID, keep highest-scoring result
            var bestByID: [String: (videoId: String, title: String, artist: String, score: Double, duration: TimeInterval?, source: String)] = [:]
            for candidate in searchCandidates {
                if let existing = bestByID[candidate.videoId] {
                    if candidate.score > existing.score {
                        bestByID[candidate.videoId] = candidate
                    }
                } else {
                    bestByID[candidate.videoId] = candidate
                }
            }

            let uniqueCandidates = Array(bestByID.values).sorted { $0.score > $1.score }
            for candidate in uniqueCandidates {
                if seenVideoIDs.contains(candidate.videoId) { continue }
                seenVideoIDs.insert(candidate.videoId)
            }

            resolverLog.notice("Search dedup: \(uniqueCandidates.count) unique video IDs from \(searchCandidates.count) results")

            // Resolve unique video IDs in parallel
            let resolvedResult: [PlaybackCandidate]? = await withTaskGroup(of: [PlaybackCandidate]?.self, returning: [PlaybackCandidate]?.self) { group in
                let phase2Spid = resolverSP.begin("yt-resolve-phase2", "count=\(uniqueCandidates.count)")
                defer { resolverSP.end("yt-resolve-phase2", state: phase2Spid, "count=\(uniqueCandidates.count)") }

                for candidate in uniqueCandidates {
                    group.addTask {
                        do {
                            let candidates = try await resolveVideoDirectly(
                                videoId: candidate.videoId,
                                title: candidate.title,
                                artist: candidate.artist,
                                mediaID: normalizedMediaID,
                                duration: candidate.duration
                            )
                            if !candidates.isEmpty {
                                resolverLog.notice("✅ Resolved '\(candidate.title, privacy: .public)' from \(candidate.source, privacy: .public) (\(candidate.videoId, privacy: .public))")
                                return candidates
                            }
                        } catch {}
                        return nil
                    }
                }

                for await result in group {
                    if let candidates = result, !candidates.isEmpty {
                        group.cancelAll()
                        return candidates
                    }
                }
                return nil
            }

            if let resolved = resolvedResult, !resolved.isEmpty {
                let totalElapsed = Date().timeIntervalSince(startTime)
                resolverLog.notice("⏱️ STREAM RESOLUTION TOOK \(String(format: "%.2f", totalElapsed))s for \(normalizedMediaID, privacy: .public)")
                await mediaCacheStore.savePlaybackResolution(mediaID: normalizedMediaID, candidates: resolved, validUntil: nil)
                return resolved
            }
        }

        throw ResolverError.decipheringFailed(videoId: youtubeVideoID)
    }

    /// Resolves a YouTube video ID directly (SDK resolve) without search.
    /// Used by search fallbacks after picking the best candidate.
    private func resolveVideoDirectly(
        videoId: String,
        title _: String,
        artist _: String,
        mediaID _: String,
        duration _: TimeInterval?
    ) async throws -> [PlaybackCandidate] {
        let info = try await YouTubeSDK.YouTubeStreamResolver.shared.resolve(
            videoId: videoId,
            preferAudio: false,
            api: nil
        )
        var candidates: [PlaybackCandidate] = []
        if let hls = info.hlsURL {
            candidates.append(PlaybackCandidate(
                url: hls,
                headers: ["User-Agent": InnerTubeClients.WebSafari.userAgent],
                streamKind: .hls,
                mimeType: "application/x-mpegURL",
                itag: nil,
                expiresAt: Date().addingTimeInterval(3600 * 4),
                isCompatible: true
            ))
        }
        if let muxed = info.bestMuxedDownloadURL {
            candidates.append(PlaybackCandidate(
                url: muxed,
                headers: ["User-Agent": InnerTubeClients.Android.userAgent],
                streamKind: .muxed,
                mimeType: "video/mp4",
                itag: nil,
                expiresAt: Date().addingTimeInterval(3600 * 4),
                isCompatible: true
            ))
        }
        return candidates
    }

    enum ResolverError: Error {
        case decipheringFailed(videoId: String)
    }

    public func cachedURL(for mediaID: String) async -> URL? {
        let normalizedMediaID = canonicalPlaybackMediaID(mediaID)
        let candidates = await mediaCacheStore.playbackCandidates(for: normalizedMediaID, maxAge: 21600)
        return candidates?.first { $0.isCompatible }?.url
    }

    // MARK: - Search result scoring

    private struct SearchCandidate {
        let videoId: String
        let title: String
        let artist: String
        let duration: TimeInterval?
    }

    private struct ScoredResult {
        let candidate: SearchCandidate
        let score: Double
        let title: String
        let artist: String
        let videoId: String
        let duration: TimeInterval?
    }

    /// Picks the best search result by scoring title overlap, artist overlap,
    /// duration proximity, and "official" markers. Returns nil if no candidate
    /// scores above the minimum threshold.
    private func pickBestSearchResult(
        from candidates: [SearchCandidate],
        sourceTitle: String,
        sourceArtist: String,
        sourceDuration: TimeInterval?
    ) -> ScoredResult? {
        guard !candidates.isEmpty else { return nil }

        let normalizedSourceTitle = normalizeForMatching(sourceTitle)
        let normalizedSourceArtist = normalizeForMatching(sourceArtist)

        let scored = candidates.map { candidate -> ScoredResult in
            let score = searchResultScore(
                candidateTitle: candidate.title,
                candidateArtist: candidate.artist,
                candidateDuration: candidate.duration,
                sourceTitle: normalizedSourceTitle,
                sourceArtist: normalizedSourceArtist,
                sourceDuration: sourceDuration
            )
            return ScoredResult(
                candidate: candidate,
                score: score,
                title: candidate.title,
                artist: candidate.artist,
                videoId: candidate.videoId,
                duration: candidate.duration
            )
        }

        let ranked = scored
            .sorted { $0.score > $1.score }

        if let best = ranked.first {
            resolverLog.debug("Search scoring: best=\(best.title, privacy: .public) score=\(best.score, privacy: .public) (top 3: \(ranked.prefix(3).map { "\($0.title.prefix(30))=\(String(format: "%.2f", $0.score))" }.joined(separator: ", "), privacy: .public))")
        }

        // Prefer candidates that pass the threshold, but if none do,
        // fall back to the top-scoring result — any video is better than failing.
        if let best = ranked.first(where: { $0.score >= 0.20 }) {
            return best
        }
        if let fallback = ranked.first {
            resolverLog.warning("No search candidates passed 0.20 threshold — using top result anyway: '\(fallback.title, privacy: .public)' (score=\(fallback.score, privacy: .public))")
            return fallback
        }
        return nil
    }

    /// Collapses spaced-out letter patterns like "s l o w e d" → "slowed".
    /// Matches 3+ single characters separated by spaces.
    private func collapseSpacedLetters(_ text: String) -> String {
        let pattern = "(?:^|\\s)(\\w)(?:\\s(\\w)){2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let nsRange = NSRange(result.startIndex..., in: result)
        // Process matches in reverse to avoid index invalidation
        let matches = regex.matches(in: result, range: nsRange).reversed()
        for match in matches {
            guard let fullRange = Range(match.range, in: result) else { continue }
            let matched = String(result[fullRange])
            let collapsed = matched.replacingOccurrences(of: " ", with: "")
            result.replaceSubrange(fullRange, with: collapsed)
        }
        return result
    }

    /// Detects variant keywords in a title string.
    /// Returns (hasStrongVariant, hasMildVariant) where strong = -0.30, mild = -0.15.
    private func detectVariants(in title: String) -> (strong: Bool, mild: Bool) {
        // Collapse spaced-out letters first: "s l o w e d" → "slowed"
        let lower = collapseSpacedLetters(title.lowercased())
        let strongMarkers = ["remix", "live", "acoustic", "cover", "instrumental",
                             "karaoke", "tribute", "mashup", "medley", "bootleg",
                             "rework", "reinterpretation", "re-recording",
                             "a cappella", "acapella", "beatbox",
                             "piano cover", "guitar cover", "ukulele"]
        let mildMarkers = ["mix", "extended", "radio edit", "club mix", "dub mix",
                           "slowed", "sped up", "nightcore", "8d",
                           "slowed and reverb", "reverb",
                           "piano version", "orchestral", "unplugged", "demo",
                           "session", "stripped", "reprise", "interlude",
                           "lo-fi", "lofi", "edit", "mono", "remaster",
                           "remastered", "version", "anniversary",
                           "deluxe", "special edition", "bonus track"]
        let hasStrong = strongMarkers.contains { lower.contains($0) }
        let hasMild = !hasStrong && mildMarkers.contains { lower.contains($0) }
        return (hasStrong, hasMild)
    }

    /// Extracts content inside parentheses/brackets and checks for hidden variant keywords.
    private func hasVariantInParentheticals(_ title: String) -> Bool {
        let pattern = "[\\(\\[]([^\\)\\]]*)[\\)\\]]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(title.startIndex..., in: title)
        let matches = regex.matches(in: title, range: range)
        for match in matches {
            if let contentRange = Range(match.range(at: 1), in: title) {
                let content = String(title[contentRange]).lowercased()
                let (_, mild) = detectVariants(in: content)
                let (_, strong) = detectVariants(in: content)
                if strong || mild { return true }
            }
        }
        return false
    }

    /// Scores a search candidate against the source track.
    /// Returns a value 0.0–1.0+ where higher is better.
    private func searchResultScore(
        candidateTitle: String,
        candidateArtist: String,
        candidateDuration: TimeInterval?,
        sourceTitle: String,
        sourceArtist: String,
        sourceDuration: TimeInterval?
    ) -> Double {
        let normalizedCandidateTitle = normalizeForMatching(candidateTitle)
        let normalizedCandidateArtist = normalizeForMatching(candidateArtist)

        // Title similarity (weight: 0.35)
        let titleScore = tokenOverlapScore(sourceTitle, normalizedCandidateTitle)

        // Artist similarity (weight: 0.25)
        let artistScore = tokenOverlapScore(sourceArtist, normalizedCandidateArtist)

        // Exact match bonuses
        let exactTitleBonus = sourceTitle == normalizedCandidateTitle ? 0.30 : 0
        let exactArtistBonus = sourceArtist == normalizedCandidateArtist ? 0.15 : 0

        // Duration proximity (weight: 0.25)
        let durationScore: Double = {
            guard let srcDur = sourceDuration, srcDur > 0,
                  let candDur = candidateDuration, candDur > 0
            else {
                return 0.05 // unknown duration — small neutral score
            }
            let delta = abs(srcDur - candDur)
            let baseline = max(srcDur, candDur, 1)
            let normalizedDelta = min(delta / baseline, 1)
            // Perfect match = 1.0, >30% delta = 0.0
            return max(0, 1 - (normalizedDelta * 3.3))
        }()

        // "Official" marker bonus
        let officialBonus: Double = {
            let lower = candidateTitle.lowercased()
            if lower.contains("official audio") || lower.contains("official video") ||
                lower.contains("official song") || lower.contains("music video") ||
                lower.contains("(lyrics)") || lower.contains("[lyrics]")
            {
                return 0.10
            }
            return 0
        }()

        // Variant penalty — check BOTH the full title AND parenthetical content
        let variantPenalty: Double = {
            let (srcStrong, srcMild) = detectVariants(in: sourceTitle)
            let (candStrong, candMild) = detectVariants(in: candidateTitle)
            let candHasParens = hasVariantInParentheticals(candidateTitle)

            // Candidate has variant but source doesn't
            if candStrong || candMild || candHasParens, !srcStrong, !srcMild {
                if candStrong || candHasParens { return -0.30 }
                return -0.15
            }
            // Source has variant but candidate doesn't
            if srcStrong || srcMild, !candStrong, !candMild {
                return -0.05
            }
            return 0
        }()

        // Title length ratio penalty — catches compilations, mixes, compilations
        let lengthPenalty: Double = {
            let candLen = normalizedCandidateTitle.count
            let srcLen = max(sourceTitle.count, 1)
            let ratio = Double(candLen) / Double(srcLen)
            if ratio > 2.0 { return -0.20 }
            if ratio > 1.5 { return -0.10 }
            return 0
        }()

        // Instrumental penalty — rank instrumental results lower unless the source is also instrumental.
        // This ensures users searching for "Song Name" don't get instrumental versions,
        // while users searching for "Song Name Instrumental" still get them.
        let instrumentalPenalty: Double = {
            let candLower = candidateTitle.lowercased()
            let srcLower = sourceTitle.lowercased()
            let candidateIsInstrumental = candLower.contains("instrumental") || candLower.contains("karaoke")
            let sourceIsInstrumental = srcLower.contains("instrumental") || srcLower.contains("karaoke")
            if candidateIsInstrumental, !sourceIsInstrumental {
                return -0.20
            }
            return 0
        }()

        return (0.35 * titleScore)
            + (0.25 * artistScore)
            + exactTitleBonus
            + exactArtistBonus
            + (0.25 * durationScore)
            + officialBonus
            + variantPenalty
            + lengthPenalty
            + instrumentalPenalty
    }

    /// Simple token overlap scoring: splits both strings into tokens and computes
    /// the Jaccard-like overlap ratio.
    private func tokenOverlapScore(_ a: String, _ b: String) -> Double {
        let tokensA = Set(a.split(separator: " ").map(String.init))
        let tokensB = Set(b.split(separator: " ").map(String.init))
        guard !tokensA.isEmpty || !tokensB.isEmpty else { return 0 }
        let intersection = tokensA.intersection(tokensB)
        let union = tokensA.union(tokensB)
        return Double(intersection.count) / Double(union.count)
    }

    /// Normalizes text for matching: lowercase, strip common parentheticals and brackets,
    /// remove punctuation.
    private func normalizeForMatching(_ text: String) -> String {
        var result = text.lowercased()
        // Remove content in parentheses and brackets: (Official Video) -> ""
        result = result.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        // Remove common suffixes like "- Topic" (YouTube auto-generated channel names)
        result = result.replacingOccurrences(of: "\\s*-\\s*topic\\s*$", with: "", options: .regularExpression)
        // Remove punctuation
        result = result.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
        // Collapse whitespace
        result = result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func canonicalPlaybackMediaID(_ mediaID: String) -> String {
        let trimmed = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("youtube-") {
            return String(trimmed.dropFirst("youtube-".count))
        }
        return trimmed
    }
}
