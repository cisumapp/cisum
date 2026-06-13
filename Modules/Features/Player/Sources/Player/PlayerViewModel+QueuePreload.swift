import Foundation
import Models
import ProviderSDK
import Utilities
import YouTubeSDK

private let queueSP = CisumSignpost.queue

@MainActor
extension PlayerViewModel {
    func preloadNextQueueEntryIfNeeded() {
        guard let queuePosition else {
            preparedNextPlayback = nil
            nextPlaybackPreloadTask?.cancel()
            nextPlaybackPreloadTask = nil
            preloadingNextMediaID = nil
            return
        }

        let nextIndex = queuePosition + 1
        guard playbackQueue.indices.contains(nextIndex) else {
            preparedNextPlayback = nil
            nextPlaybackPreloadTask?.cancel()
            nextPlaybackPreloadTask = nil
            preloadingNextMediaID = nil
            return
        }

        let nextEntry = playbackQueue[nextIndex]
        if preparedNextPlayback?.mediaID == nextEntry.mediaID {
            return
        }

        if preloadingNextMediaID == nextEntry.mediaID,
           nextPlaybackPreloadTask != nil
        {
            return
        }

        preparedNextPlayback = nil
        nextPlaybackPreloadTask?.cancel()
        preloadingNextMediaID = nextEntry.mediaID
        let preloadSpid = queueSP.begin("next-preload", "id=\(nextEntry.mediaID)")
        nextPlaybackPreloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.preloadingNextMediaID == nextEntry.mediaID {
                    self.preloadingNextMediaID = nil
                }
                queueSP.end("next-preload", state: preloadSpid, "id=\(nextEntry.mediaID)")
            }

            let prepared = await prepareQueuePlayback(for: nextEntry)
            guard !Task.isCancelled,
                  let prepared,
                  let currentQueuePosition = self.queuePosition
            else {
                return
            }

            let expectedIndex = currentQueuePosition + 1
            guard playbackQueue.indices.contains(expectedIndex),
                  playbackQueue[expectedIndex].mediaID == prepared.mediaID
            else {
                return
            }

            PerfLog.info("Preload ready id=\(prepared.mediaID) quality=\(prepared.qualityLabel)")
            preparedNextPlayback = prepared
        }
        preloadDistantQueueEntries()
    }

    /// Schedules a time-based prewarming task that re-preloads the next track
    /// when we're 30 seconds from the end of the current track.
    /// This ensures the prepared playback is fresh even for long tracks.
    func scheduleTimeBasedPrewarming() {
        timeBasedPrewarmTask?.cancel()
        timeBasedPrewarmTask = nil

        let trackDuration = duration
        guard trackDuration > 60 else { return }

        // Trigger prewarming 30 seconds before track ends (or at 70% mark, whichever is later)
        let triggerOffset = max(30, trackDuration * 0.7)
        let delay = max(0, trackDuration - triggerOffset)

        timeBasedPrewarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            PerfLog.info("Time-based prewarm triggered for next track (\(String(format: "%.0f", delay))s into \(String(format: "%.0f", trackDuration))s track)")
            preloadNextQueueEntryIfNeeded()
        }
    }

    private func prepareQueuePlayback(for entry: PlaybackQueueEntry) async -> PreparedQueuePlayback? {
        do {
            switch entry {
            case let .song(song):
                return try await prepareMusicQueuePlayback(
                    QueueMusicPreloadInput(
                        mediaID: song.videoId,
                        title: song.title,
                        artist: song.artistsDisplay,
                        albumName: song.album,
                        artworkURL: song.thumbnailURL,
                        isExplicit: song.isExplicit,
                        durationHint: Self.lyricsDurationHint(from: song.duration),
                        youtubeDebugSource: "youtube-fallback"
                    )
                )

            case let .cachedRadio(track):
                return try await prepareMusicQueuePlayback(
                    QueueMusicPreloadInput(
                        mediaID: track.videoID,
                        title: track.title,
                        artist: track.artist,
                        albumName: track.albumName,
                        artworkURL: track.thumbnailURL,
                        isExplicit: track.isExplicit,
                        durationHint: nil,
                        youtubeDebugSource: "radio-youtube-fallback"
                    )
                )

            case let .video(video):
                let displayTitle = normalizedMusicDisplayTitle(video.title, artist: video.author)
                let displayArtist = normalizedMusicDisplayArtist(video.author, title: video.title)
                let representation = TrackRepresentation(
                    providerID: "youtube",
                    providerTrackID: video.id,
                    title: displayTitle,
                    artist: displayArtist,
                    artworkURL: normalizedArtworkURL(from: video.thumbnailURL)
                )
                let candidates = try await resolvePlaybackCandidates(
                    forID: video.id,
                    title: video.title ?? "",
                    artist: video.author ?? "",
                    representations: [representation]
                )
                guard let candidate = candidates.first else { return nil }
                let labels = playbackLabels(for: candidate)

                let prepared = PreparedQueuePlayback(
                    mediaID: video.id,
                    item: makePlayerItem(for: candidate.url, service: .youtube),
                    playbackCandidates: candidates,
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                    artist: normalizedMusicDisplayArtist(video.author, title: video.title),
                    artworkURL: normalizedArtworkURL(from: video.thumbnailURL),
                    streamingService: .youtube,
                    qualityLabel: labels.quality,
                    codecLabel: labels.codec,
                    albumName: nil,
                    isExplicit: false,
                    durationHint: Self.lyricsDurationHint(from: video.lengthInSeconds)
                )
                debugQueuePreloadSelection(prepared, source: "youtube-video")
                return prepared

            case let .external(track):
                let normalizedMediaID = track.mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedMediaID.isEmpty else { return nil }

                // Check cache first (MainActor-isolated, must be before task group)
                if let cachedPayload = externalPayloadCache[normalizedMediaID] {
                    let streamingService = Self.streamingService(for: cachedPayload.service)
                    let candidate = PlaybackCandidate(
                        url: cachedPayload.streamURL, streamKind: .audio,
                        mimeType: mimeTypeForCodecLabel(cachedPayload.codecLabel),
                        itag: nil, expiresAt: nil, isCompatible: true
                    )
                    let prepared = PreparedQueuePlayback(
                        mediaID: normalizedMediaID,
                        item: makePlayerItem(for: cachedPayload.streamURL, service: streamingService),
                        playbackCandidates: [candidate], preparedAt: .now,
                        title: normalizedMusicDisplayTitle(cachedPayload.title, artist: cachedPayload.artist),
                        artist: normalizedMusicDisplayArtist(cachedPayload.artist, title: cachedPayload.title),
                        artworkURL: cachedPayload.artworkURL ?? track.artworkURL,
                        streamingService: streamingService,
                        qualityLabel: cachedPayload.qualityLabel, codecLabel: cachedPayload.codecLabel,
                        albumName: nil, isExplicit: track.isExplicit, durationHint: nil
                    )
                    debugQueuePreloadSelection(prepared, source: "external-cached")
                    return prepared
                }

                // Race both resolution paths in parallel
                let payload: ExternalStreamPayload? = await withTaskGroup(of: ExternalStreamPayload?.self, returning: ExternalStreamPayload?.self) { group in
                    // Path A: Primary resolvePayload
                    group.addTask {
                        do { return try await track.resolvePayload() }
                        catch { return nil }
                    }
                    // Path B: YouTube fallback
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        do {
                            let candidates = try await resolvePlaybackCandidates(
                                forID: normalizedMediaID, title: track.title, artist: track.artist
                            )
                            guard let best = candidates.first else { return nil }
                            return ExternalStreamPayload(
                                mediaID: normalizedMediaID, streamURL: best.url,
                                title: track.title, artist: track.artist,
                                artworkURL: track.artworkURL, service: track.service,
                                qualityLabel: track.qualityLabelHint ?? "YouTube",
                                codecLabel: track.codecLabelHint ?? "HLS"
                            )
                        } catch { return nil }
                    }
                    for await result in group {
                        if let result { group.cancelAll(); return result }
                    }
                    return nil
                }
                guard let payload else { return nil }

                let streamingService = Self.streamingService(for: payload.service)
                let candidate = PlaybackCandidate(
                    url: payload.streamURL,
                    streamKind: .audio,
                    mimeType: mimeTypeForCodecLabel(payload.codecLabel),
                    itag: nil,
                    expiresAt: nil,
                    isCompatible: true
                )
                let prepared = PreparedQueuePlayback(
                    mediaID: normalizedMediaID,
                    item: makePlayerItem(for: payload.streamURL, service: streamingService),
                    playbackCandidates: [candidate],
                    preparedAt: .now,
                    title: normalizedMusicDisplayTitle(payload.title, artist: payload.artist),
                    artist: normalizedMusicDisplayArtist(payload.artist, title: payload.title),
                    artworkURL: payload.artworkURL ?? track.artworkURL,
                    streamingService: streamingService,
                    qualityLabel: payload.qualityLabel,
                    codecLabel: payload.codecLabel,
                    albumName: nil,
                    isExplicit: track.isExplicit,
                    durationHint: nil
                )
                debugQueuePreloadSelection(prepared, source: "external-\(payload.service.rawValue)")
                return prepared
            }
        } catch {
            logPlayback("Queue preload failed for mediaID=\(entry.mediaID): \(error.localizedDescription)")
            return nil
        }
    }

    private func prepareMusicQueuePlayback(_ input: QueueMusicPreloadInput) async throws -> PreparedQueuePlayback? {
        let displayTitle = normalizedMusicDisplayTitle(input.title, artist: input.artist)
        let displayArtist = normalizedMusicDisplayArtist(input.artist, title: input.title)
        let representation = TrackRepresentation(
            providerID: "youtubeMusic",
            providerTrackID: input.mediaID,
            title: displayTitle,
            artist: displayArtist,
            album: input.albumName,
            artworkURL: input.artworkURL
        )
        let candidates = try await resolvePlaybackCandidates(
            forID: input.mediaID,
            title: input.title,
            artist: input.artist,
            representations: [representation]
        )
        guard let candidate = candidates.first else { return nil }

        let labels = playbackLabels(for: candidate)
        let prepared = PreparedQueuePlayback(
            mediaID: input.mediaID,
            item: makePlayerItem(for: candidate.url, service: .youtubeMusic),
            playbackCandidates: candidates,
            preparedAt: .now,
            title: normalizedMusicDisplayTitle(input.title, artist: input.artist),
            artist: normalizedMusicDisplayArtist(input.artist, title: input.title),
            artworkURL: input.artworkURL,
            streamingService: .youtubeMusic,
            qualityLabel: labels.quality,
            codecLabel: labels.codec,
            albumName: input.albumName,
            isExplicit: input.isExplicit,
            durationHint: input.durationHint
        )
        debugQueuePreloadSelection(prepared, source: input.youtubeDebugSource)
        return prepared
    }

    private func debugQueuePreloadSelection(_ prepared: PreparedQueuePlayback, source: String) {
                PerfLog.debug("[QUEUE]: {source: \(source), mediaID: \(prepared.mediaID), title: \(prepared.title), artist: \(prepared.artist), service: \(prepared.streamingService.rawValue), quality: \(prepared.qualityLabel), codec: \(prepared.codecLabel), queueSource: \(queueSource.rawValue), queuePosition: \(queuePosition ?? -1), queueCount: \(queueCount)}")
    }

    /// Pre-resolves the next 2-5 queue entries in parallel background tasks.
    /// Results are cached in `distantPreloadCache` and consumed when the queue advances.
    func preloadDistantQueueEntries() {
        guard let queuePosition else { return }

        distantPreloadTasks.forEach { $0.cancel() }
        distantPreloadTasks.removeAll()

        let maxLookahead = min(5, playbackQueue.count - queuePosition - 1)
        guard maxLookahead >= 2 else { return }

        for offset in 2 ... maxLookahead {
            let index = queuePosition + offset
            guard playbackQueue.indices.contains(index) else { continue }
            let entry = playbackQueue[index]

            if distantPreloadCache[entry.mediaID] != nil { continue }

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                let prepared = await prepareQueuePlayback(for: entry)
                guard !Task.isCancelled, let prepared else { return }
                distantPreloadCache[prepared.mediaID] = prepared
                PerfLog.info("Distant preload ready id=\(prepared.mediaID) offset=\(offset)")
            }
            distantPreloadTasks.append(task)
        }
    }

    /// Returns a pre-resolved playback item for the given mediaID, if available.
    /// Consumes from `distantPreloadCache` and removes the entry.
    func consumeDistantPreload(for mediaID: String) -> PreparedQueuePlayback? {
        distantPreloadCache.removeValue(forKey: mediaID)
    }
}
