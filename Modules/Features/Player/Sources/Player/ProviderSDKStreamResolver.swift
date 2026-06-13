import Caching
import Foundation
import Models
import ProviderSDK
import Utilities

public struct ProviderSDKStreamResolver: StreamResolutionProvider {
    private let providerSDK: ProviderSDK
    private let mediaCacheStore: MediaCacheStore

    public init(providerSDK: ProviderSDK, mediaCacheStore: MediaCacheStore) {
        self.providerSDK = providerSDK
        self.mediaCacheStore = mediaCacheStore
    }

    public func resolveStream(
        mediaID: String,
        title: String,
        artist: String,
        representations: [TrackRepresentation]? = nil,
        forceDecipher: Bool,
        duration: TimeInterval? = nil
    ) async throws -> [PlaybackCandidate] {
        let normalizedMediaID = canonicalPlaybackMediaID(mediaID)
        PerfLog.debug("ProviderSDKStreamResolver: resolving \(normalizedMediaID) title=\(title) artist=\(artist) representations=\(representations?.count ?? 0)")

        if !forceDecipher,
           let cachedCandidates = await mediaCacheStore.playbackCandidates(for: normalizedMediaID, maxAge: 21600),
           let cachedCandidate = cachedCandidates.first(where: { $0.isCompatible })
        {
            PerfLog.debug("ProviderSDKStreamResolver: cached resolution hit for \(normalizedMediaID)")
            return [cachedCandidate]
        }

        var matchedTrack: Track?
        var resolvedAudioStreams: [AudioStream] = []
        var resolutionError: Error?

        // 1. If representations are provided, try to resolve using them directly
        if let reps = representations, !reps.isEmpty {
            let unknownArtist = Artist(id: ArtistIdentifier(provider: "unknown", value: "unknown"), name: artist)
            let unknownAlbum = Album(id: AlbumIdentifier(provider: "unknown", value: "unknown"), title: "Unknown", artist: unknownArtist)
            let canonicalID = canonicalTrackID(title: title, artist: artist, representations: reps)

            let constructedTrack = Track(
                id: canonicalID,
                title: title,
                artists: [unknownArtist],
                album: unknownAlbum,
                isrc: reps.compactMap(\.isrc).first.flatMap { try? ISRC($0) },
                duration: 0,
                representations: reps,
                activeRepresentationKey: reps.first?.representationKey,
                hydrationState: [.metadataResolved],
                confidence: reps.first.map { rep in
                    ConfidenceBreakdown(
                        metadata: 0.7,
                        identity: rep.isrc == nil ? 0.5 : 1.0,
                        artwork: rep.canResolveArtwork ? 0.8 : 0.5,
                        streamReliability: rep.canResolvePlayback ? 0.9 : 0.4,
                        sourceTrust: rep.confidenceScore
                    )
                } ?? ConfidenceBreakdown(),
                metadata: canonicalMetadata(for: normalizedMediaID, representations: reps)
            )

            matchedTrack = constructedTrack

            do {
                let stream = try await providerSDK.resolveStream(for: constructedTrack, quality: .high)
                resolvedAudioStreams = [stream]
            } catch {
                resolutionError = error
                PerfLog.debug("ProviderSDKStreamResolver: stream resolution with provided representations failed: \(error.localizedDescription)")
                // Clear the stream so we fall back to ISRC lookup or federated search
                resolvedAudioStreams = []
            }
        }

        // 1.5 Fallback: Search by ISRC if available and we don't have a stream yet
        if resolvedAudioStreams.isEmpty, let isrcStr = representations?.compactMap(\.isrc).first, let isrc = try? ISRC(isrcStr) {
            PerfLog.debug("ProviderSDKStreamResolver: falling back to ISRC lookup for: '\(isrcStr)'")
            if let track = try? await providerSDK.getTrackByISRC(isrc) {
                if let stream = try? await providerSDK.resolveStream(for: track, quality: .high) {
                    resolvedAudioStreams = [stream]
                    matchedTrack = track
                    PerfLog.debug("ProviderSDKStreamResolver: ISRC lookup successful for \(isrcStr) using provider: \(stream.provider)")
                }
            }
        }

        // 2. Fallback: Search across federation to find the track representation if we don't have a stream yet
        var searchTitle = title
        var searchArtist = artist

        if artist.lowercased() == "unknown" || artist.isEmpty {
            if let spotifyRep = representations?.first(where: { $0.providerID == "spotify" }) {
                searchTitle = spotifyRep.title
                searchArtist = spotifyRep.artist
            } else {
                searchArtist = ""
            }
        }

        let query = "\(searchTitle) \(searchArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedAudioStreams.isEmpty, !query.isEmpty {
            PerfLog.debug("ProviderSDKStreamResolver: falling back to federated search for: '\(query)'")
            let searchStream = await providerSDK.searchTracks(query: query, limit: 1)

            // C-3 fix: append on each yield so a single-provider error doesn't discard
            // tracks already received from other providers in the async stream.
            var finalTracks: [Track] = []
            do {
                for try await batch in searchStream {
                    finalTracks.append(contentsOf: batch) // was: = batch (overwrote on every yield)
                }
            } catch {
                // A provider failure mid-stream is non-fatal — use whatever we accumulated.
                PerfLog.debug("ProviderSDKStreamResolver: federated search stream error (partial results kept): \(error.localizedDescription)")
            }

            /// Score each track against the target metadata
            func scoreTrack(_ track: Track) -> Double {
                let candidateArtists = track.artists.map(\.name).joined(separator: " ")
                let candidateTitle = track.title

                let titleScore = Utilities.tokenOverlapScore(searchTitle, candidateTitle)
                let artistScore = Utilities.tokenOverlapScore(searchArtist, candidateArtists)

                // Duration proximity score
                let durationScore: Double = {
                    guard let srcDur = duration, srcDur > 0, track.duration > 0 else { return 0 }
                    let delta = abs(srcDur - track.duration)
                    let baseline = max(srcDur, track.duration, 1)
                    let normalizedDelta = min(delta / baseline, 1)
                    return max(0, 1 - (normalizedDelta * 3.3))
                }()

                return (titleScore * 0.55) + (artistScore * 0.35) + (durationScore * 0.10)
            }

            // Filter out tracks that are completely irrelevant to the search query
            let filteredTracks = finalTracks.filter { track in
                let candidateArtists = track.artists.map(\.name).joined(separator: " ")
                let candidateTitle = track.title

                let titleScore = Utilities.tokenOverlapScore(searchTitle, candidateTitle)
                let artistScore = Utilities.tokenOverlapScore(searchArtist, candidateArtists)

                let isArtistUnknown = searchArtist.lowercased() == "unknown" || searchArtist.isEmpty

                let passes: Bool = if isArtistUnknown {
                    titleScore >= 0.6
                } else {
                    // Must have decent title match AND good artist match
                    titleScore >= 0.5 && artistScore >= 0.5
                }

                let trackFullText = "\(candidateTitle) \(candidateArtists)"
                PerfLog.debug("ProviderSDKStreamResolver: federated candidate '\(trackFullText)' titleScore: \(titleScore) artistScore: \(artistScore) (passes: \(passes))")
                return passes
            }

            // M-1: Concurrent stream resolution across federated results
            typealias ResolutionResult = (stream: AudioStream, track: Track)

            var results = await withTaskGroup(of: Result<ResolutionResult, Error>.self, returning: [ResolutionResult].self) { group in
                for track in filteredTracks {
                    group.addTask {
                        do {
                            let stream = try await providerSDK.resolveStream(for: track, quality: .high)
                            return .success((stream, track))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var successes: [ResolutionResult] = []
                for await result in group {
                    switch result {
                    case let .success(payload):
                        successes.append(payload)
                    case let .failure(error):
                        PerfLog.debug("ProviderSDKStreamResolver: stream resolution failed. Error: \(error.localizedDescription)")
                    }
                }

                return successes
            }

            if !results.isEmpty {
                // Sort the successfully resolved tracks by metadata score to ensure the best match wins the race
                results.sort { scoreTrack($0.track) > scoreTrack($1.track) }

                // Just use the highest scoring one for `matchedTrack` and logging.
                let bestResult = results[0]
                PerfLog.debug("ProviderSDKStreamResolver: successfully resolved streams via ProviderSDK (count: \(results.count)). Selected best match: \(bestResult.track.title) (score: \(scoreTrack(bestResult.track)))")

                resolvedAudioStreams = [bestResult.stream]
                matchedTrack = bestResult.track
            } else {
                resolutionError = resolutionError ?? NSError(domain: "ProviderSDKStreamResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "All federated tracks failed to resolve stream"])
            }
        }

        guard let track = matchedTrack else {
            throw resolutionError ?? NSError(domain: "ProviderSDKStreamResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track not found across providers for: \(title) \(artist)"])
        }

        let sourceProviders = Dictionary(grouping: track.representations, by: { $0.providerID })
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")

        PerfLog.debug("ProviderSDKStreamResolver: matched track \(track.id.value) source_providers=[\(sourceProviders)] active_representation=\(track.activeRepresentationKey?.providerID ?? "none")")

        guard !resolvedAudioStreams.isEmpty else {
            throw resolutionError ?? NSError(domain: "ProviderSDKStreamResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve stream after federated fallback"])
        }

        let candidates = resolvedAudioStreams.map { audioStream in
            PerfLog.debug("ProviderSDKStreamResolver: resolved stream provider=\(audioStream.provider) quality=\(audioStream.quality.rawValue) url=\(audioStream.url.absoluteString)")
            return Caching.PlaybackCandidate(
                url: audioStream.url,
                streamKind: Self.streamKind(for: audioStream.url),
                mimeType: Self.mimeType(for: audioStream),
                itag: nil,
                expiresAt: audioStream.expiresAt,
                isCompatible: true,
                providerID: audioStream.provider
            )
        }

        await mediaCacheStore.savePlaybackResolution(mediaID: normalizedMediaID, candidates: candidates, validUntil: resolvedAudioStreams.first?.expiresAt)

        return candidates
    }

    public func cachedURL(for mediaID: String) async -> URL? {
        let normalizedMediaID = canonicalPlaybackMediaID(mediaID)
        let candidates = await mediaCacheStore.playbackCandidates(for: normalizedMediaID, maxAge: 21600)
        if let url = candidates?.first(where: { $0.isCompatible })?.url {
            PerfLog.debug("ProviderSDKStreamResolver: cached URL hit for \(normalizedMediaID)")
            return url
        }

        return nil
    }

    // MARK: - Quality Metadata Helpers

    /// Maps an `AudioStream`'s codec and quality tier to a MIME type string that
    /// the Player's `playbackLabels(for:)` function can use to surface accurate
    /// quality labels (e.g., "FLAC 24-bit", "Hi-Res Lossless").
    private static func mimeType(for stream: AudioStream) -> String {
        switch stream.codec.codec {
        case .flac:
            return "audio/flac"
        case .alac:
            return "audio/alac"
        case .dsd:
            return "audio/dsd"
        case .aac:
            // Distinguish high-quality AAC (e.g. 256+ kbps) from standard
            if let bitrate = stream.codec.bitrate, bitrate >= 256 {
                return "audio/aac; bitrate=\(bitrate)"
            }
            return "audio/aac"
        case .mp3:
            if let bitrate = stream.codec.bitrate {
                return "audio/mpeg; bitrate=\(bitrate)"
            }
            return "audio/mpeg"
        case .opus:
            return "audio/ogg; codecs=opus"
        case .vorbis:
            return "audio/ogg"
        case .wma:
            return "audio/x-ms-wma"
        case let .other(name):
            // Fallback: encode the quality tier so PlayerViewModel can still rank it.
            return "audio/x-unknown; quality=\(stream.quality.rawValue); codec=\(name)"
        }
    }

    /// Infers the correct `StreamKind` for an `AudioStream` URL.
    /// HLS manifests (.m3u8) should be played via the `.hls` path so AVPlayer
    /// uses its adaptive bitrate logic; everything else is a direct audio stream.
    private static func streamKind(for url: URL) -> PlaybackCandidate.StreamKind {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" { return .hls }
        // SoundCloud and most direct-link providers return bare audio files.
        return .audio
    }

    private func canonicalPlaybackMediaID(_ mediaID: String) -> String {
        let trimmed = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("youtube-") {
            return String(trimmed.dropFirst("youtube-".count))
        }
        return trimmed
    }

    private func canonicalTrackID(title: String, artist: String, representations: [TrackRepresentation]) -> CanonicalID {
        if let isrc = representations.compactMap(\.isrc).first, !isrc.isEmpty {
            return CanonicalID.from(isrc: isrc)
        }

        let fingerprint = "\(title.lowercased())|\(artist.lowercased())"
        return CanonicalID.from(hash: String(format: "%016lx", UInt(bitPattern: fingerprint.hashValue)))
    }

    private func canonicalMetadata(for mediaID: String, representations: [TrackRepresentation]) -> [String: String] {
        var metadata: [String: String] = [
            "source_media_id": mediaID,
            "provider_track_id": representations.first?.providerTrackID ?? mediaID,
            "provider_id": representations.first?.providerID ?? "unknown",
        ]

        if let firstRepresentation = representations.first {
            metadata["active_representation_key"] = "\(firstRepresentation.providerID):\(firstRepresentation.providerTrackID)"
        }

        return metadata
    }
}
