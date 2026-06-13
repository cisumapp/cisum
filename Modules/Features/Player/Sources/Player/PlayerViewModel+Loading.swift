//
//  PlayerViewModel+Loading.swift
//  cisum
//

import Foundation
import Models
import ProviderSDK
import Utilities
import YouTubeSDK
#if canImport(WebKit)
import WebKit
#endif

private let loadingSP = CisumSignpost.playback

public extension PlayerViewModel {
    // MARK: - Loaders

    func load(external track: ExternalQueueTrack, preserveQueue: Bool = false) {
        loadExternalTrack(track, preserveQueue: preserveQueue)
    }

    func setQueue(_ tracks: [ExternalQueueTrack], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        let entries = tracks.map { PlaybackQueueEntry.external($0) }
        playbackQueue = entries
        queueCount = entries.count
        queueSource = .userQueue
        queuePosition = startIndex
        if entries.indices.contains(startIndex) {
            load(entry: entries[startIndex])
        }
    }

    func load(song: YouTubeMusicSong, preserveQueue: Bool = false) {
        // Patch 3: Skip if we are already actively loading this exact track.
        if song.videoId == loadingMediaID, isLoading { return }

        loadMusicTrack(
            mediaID: song.videoId,
            title: song.title,
            artist: song.artistsDisplay,
            albumName: song.album,
            thumbnailURL: song.thumbnailURL,
            explicit: song.isExplicit,
            durationHint: Self.lyricsDurationHint(from: song.duration),
            preserveQueue: preserveQueue
        )

        if !preserveQueue {
            seedRadioQueue(from: song)
        }
    }

    func load(video: YouTubeVideo, preserveQueue: Bool = false) {
        // Patch 3
        if video.id == loadingMediaID, isLoading { return }
        let targetMediaID = video.id

        let tapStartedAt = Date()
        let tapToPlaySpid = loadingSP.begin("tap-to-play", "kind=video id=\(targetMediaID)")

        pendingPlaybackTelemetryType = "tap-to-play"
        pendingPlaybackTelemetryStartedAt = tapStartedAt

        let fallbackURL = normalizedArtworkURL(from: video.thumbnailURL)
        let displayTitle = normalizedMusicDisplayTitle(video.title, artist: video.author)
        let displayArtist = normalizedMusicDisplayArtist(video.author, title: video.title)

        let presentation = TrackPresentationState(
            mediaID: targetMediaID,
            title: displayTitle,
            artist: displayArtist,
            albumName: nil,
            artworkURL: fallbackURL,
            isExplicit: false,
            streamingService: .youtube,
            qualityLabel: "Resolving...",
            codecLabel: "Resolving...",
            durationHint: Self.lyricsDurationHint(from: video.lengthInSeconds),
            queueIdentity: makeQueueIdentitySnapshot(
                mediaID: targetMediaID,
                title: displayTitle,
                artist: displayArtist,
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        )
        preparePlaybackSession(for: presentation, preserveQueue: preserveQueue)

        isLoading = true
        loadingMediaID = targetMediaID
        currentLoadTask?.cancel()

        // Fire-and-forget: start BotGuard WKWebView warm-up so a minted poToken is
        // available for CDN segment auth when the HLS proxy needs it. This runs
        // concurrently with candidate resolution — no added latency.
        #if canImport(WebKit)
        Task { @MainActor in
            let result = await BotGuardWebViewRunner.shared.prepare(for: video.id)
            // SAPISID recovery: BotGuardWebViewRunner.prepare() calls propagateWebViewCookies()
            // which copies youtube.com cookies (including SAPISID) from the WKWebView session
            // into HTTPCookieStorage.shared. Recovering SAPISID here enables SAPISIDHASH auth
            // in postWebSafari — YouTube returns rqh=0 adaptive URLs that the CDN serves
            // without pot= enforcement.
            if let webSAPISID = HTTPCookieStorage.shared
                .cookies(for: URL(string: "https://www.youtube.com")!)?
                .first(where: { $0.name == "SAPISID" })?.value
            {
                await YouTubeSDK.YouTubeStreamResolver.shared.api.setSAPISID(webSAPISID)
            }
            let oauthToken = await YouTubeOAuthClient().getAccessToken()
            await YouTubeSDK.YouTubeStreamResolver.shared.api.updateAuthToken(oauthToken)
            if result?.hasMinter == true,
               let token = await BotGuardWebViewRunner.shared.mintToken(
                   identifier: YouTubeSDK.YouTubeStreamResolver.shared.api.currentVisitorData() ?? ""
               )
            {
                await YouTubeSDK.YouTubeStreamResolver.shared.api.storeExternalPoToken(token, for: video.id)
            }
        }
        #endif

        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.loadingMediaID == targetMediaID { self.isLoading = false }
                loadingSP.end("tap-to-play", state: tapToPlaySpid, "kind=video id=\(targetMediaID)")
            }
            if Task.isCancelled { return }

            do {
                let representation = TrackRepresentation(
                    providerID: "youtube",
                    providerTrackID: video.id,
                    title: displayTitle,
                    artist: displayArtist,
                    artworkURL: fallbackURL
                )
                let candidates = try await resolvePlaybackCandidates(
                    forID: video.id,
                    title: video.title ?? "",
                    artist: video.author ?? "",
                    representations: [representation]
                )

                if Task.isCancelled { return }
                guard currentVideoId == targetMediaID else { return }

                PerfLog.info("Candidates resolved id=\(targetMediaID) count=\(candidates.count)")
                configurePlaybackCandidates(for: video.id, candidates: candidates)
                playCurrentPlaybackCandidate()
                startArtworkVideoProcessingIfNeeded(
                    for: video.id,
                    title: displayTitle,
                    artist: displayArtist,
                    albumName: nil
                )
                logPlayback("Started playback for video id=\(video.id)")

                if !preserveQueue {
                    seedRadioQueueForVideoTrack(
                        video: video,
                        expectedCurrentMediaID: targetMediaID
                    )
                }

                loadingSP.event("preload-next", "trigger=video id=\(targetMediaID)")
                preloadNextQueueEntryIfNeeded()

                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                    PerfLog.info("tap-to-play latency=\(elapsed)ms id=\(targetMediaID)")
                }
            } catch {
                if error is CancellationError { return }
                guard currentVideoId == targetMediaID else { return }
                handlePlaybackFailure(error)
            }
        }
    }

    func load(resolvedPlaybackSession session: ResolvedPlaybackSession, preserveQueue: Bool = false) {
        let track = session.playableTrack.track
        let title = track.title
        let artist = track.artists.map(\.name).joined(separator: ", ")
        let albumName = track.album.title
        let activeCandidate = session.selectedCandidate
        let hydrationLabels: [String] = [
            track.hydrationState.contains(.metadataResolved) ? "metadataResolved" : nil,
            track.hydrationState.contains(.artworkResolved) ? "artworkResolved" : nil,
            track.hydrationState.contains(.streamResolved) ? "streamResolved" : nil,
            track.hydrationState.contains(.lyricsResolved) ? "lyricsResolved" : nil,
        ].compactMap(\.self)
        let representationKey = track.activeRepresentationKey.map { "\($0.providerID):\($0.providerTrackID)" }

        let presentation = TrackPresentationState(
            mediaID: track.id.value,
            title: title,
            artist: artist,
            albumName: albumName,
            artworkURL: track.externalURL,
            isExplicit: track.isExplicit,
            streamingService: .external,
            qualityLabel: session.stream.quality.displayName,
            codecLabel: session.stream.codec.formatDescription,
            durationHint: Int(track.duration),
            queueIdentity: makeQueueIdentitySnapshot(
                mediaID: track.id.value,
                title: title,
                artist: artist,
                activeRepresentationKey: representationKey,
                hydrationState: hydrationLabels,
                candidateSnapshot: [
                    QueueCandidateSnapshot(
                        streamKind: session.stream.provider,
                        mimeType: session.stream.metadata["mimeType"],
                        itag: nil,
                        expiresAt: session.stream.expiresAt,
                        isCompatible: activeCandidate.isLocal,
                        providerID: session.stream.provider
                    ),
                ]
            )
        )

        preparePlaybackSession(for: presentation, preserveQueue: preserveQueue)

        let localCandidate = PlaybackCandidate(
            url: session.stream.url,
            streamKind: .audio,
            mimeType: session.stream.metadata["mimeType"] ?? session.stream.codec.formatDescription,
            itag: nil,
            expiresAt: session.stream.expiresAt,
            isCompatible: true,
            providerID: session.stream.provider
        )

        configurePlaybackCandidates(for: track.id.value, candidates: [localCandidate])
        playCurrentPlaybackCandidate()
    }

    internal func loadMusicTrack(
        mediaID: String,
        title: String,
        artist: String,
        albumName: String?,
        thumbnailURL: URL?,
        explicit: Bool,
        durationHint: Int?,
        preserveQueue: Bool
    ) {
        let targetMediaID = mediaID

        let tapStartedAt = Date()
        let tapToPlaySpid = loadingSP.begin("tap-to-play", "kind=song id=\(targetMediaID)")

        pendingPlaybackTelemetryType = "tap-to-play"
        pendingPlaybackTelemetryStartedAt = tapStartedAt

        let displayTitle = normalizedMusicDisplayTitle(title, artist: artist)
        let displayArtist = normalizedMusicDisplayArtist(artist, title: title)

        let presentation = TrackPresentationState(
            mediaID: mediaID,
            title: displayTitle,
            artist: displayArtist,
            albumName: albumName,
            artworkURL: thumbnailURL,
            isExplicit: explicit,
            streamingService: .youtube,
            qualityLabel: "Resolving...",
            codecLabel: "Resolving...",
            durationHint: durationHint,
            queueIdentity: makeQueueIdentitySnapshot(
                mediaID: mediaID,
                title: displayTitle,
                artist: displayArtist,
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        )
        preparePlaybackSession(for: presentation, preserveQueue: preserveQueue)

        isLoading = true
        loadingMediaID = targetMediaID
        currentLoadTask?.cancel()

        // Fire-and-forget: start BotGuard WKWebView warm-up for music tracks too.
        #if canImport(WebKit)
        Task { @MainActor in
            let result = await BotGuardWebViewRunner.shared.prepare(for: mediaID)
            if let webSAPISID = HTTPCookieStorage.shared
                .cookies(for: URL(string: "https://www.youtube.com")!)?
                .first(where: { $0.name == "SAPISID" })?.value
            {
                await YouTubeSDK.YouTubeStreamResolver.shared.api.setSAPISID(webSAPISID)
            }
            let oauthToken = await YouTubeOAuthClient().getAccessToken()
            await YouTubeSDK.YouTubeStreamResolver.shared.api.updateAuthToken(oauthToken)
            if result?.hasMinter == true,
               let token = await BotGuardWebViewRunner.shared.mintToken(
                   identifier: YouTubeSDK.YouTubeStreamResolver.shared.api.currentVisitorData() ?? ""
               )
            {
                await YouTubeSDK.YouTubeStreamResolver.shared.api.storeExternalPoToken(token, for: mediaID)
            }
        }
        #endif

        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.loadingMediaID == targetMediaID { self.isLoading = false }
                loadingSP.end("tap-to-play", state: tapToPlaySpid, "kind=song id=\(targetMediaID)")
            }
            if Task.isCancelled { return }

            do {
                let representation = TrackRepresentation(
                    providerID: "youtubeMusic",
                    providerTrackID: mediaID,
                    title: displayTitle,
                    artist: displayArtist,
                    album: albumName,
                    artworkURL: thumbnailURL
                )
                // Resolve YouTube candidates and start playback immediately.
                let youtubeCandidates = try await resolvePlaybackCandidates(
                    forID: mediaID,
                    title: title,
                    artist: artist,
                    representations: [representation]
                )

                if Task.isCancelled { return }
                guard currentVideoId == targetMediaID else { return }

                PerfLog.info("Candidates resolved id=\(targetMediaID) count=\(youtubeCandidates.count)")
                configurePlaybackCandidates(for: mediaID, candidates: youtubeCandidates)
                playCurrentPlaybackCandidate()
                startArtworkVideoProcessingIfNeeded(
                    for: mediaID,
                    title: currentTitle,
                    artist: currentArtist,
                    albumName: albumName
                )
                logPlayback("Started playback for song id=\(mediaID)")
                loadingSP.event("preload-next", "trigger=song id=\(targetMediaID)")
                preloadNextQueueEntryIfNeeded()

                if settings.metricsEnabled {
                    let elapsed = Date().timeIntervalSince(tapStartedAt) * 1000
                    await playbackMetricsStore.recordTapToPlay(durationMs: elapsed)
                    PerfLog.info("tap-to-play latency=\(elapsed)ms id=\(targetMediaID)")
                }

            } catch {
                if error is CancellationError { return }
                guard currentVideoId == targetMediaID else { return }
                handlePlaybackFailure(error)
            }
        }
    }

    func loadExternalStream(
        mediaID: String,
        streamURL: URL,
        title: String,
        artist: String,
        artworkURL: URL?,
        service: FederatedService,
        qualityLabel: String,
        codecLabel: String
    ) {
        let immediateTrack = ExternalQueueTrack(
            mediaID: mediaID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            service: service,
            isExplicit: false,
            qualityLabelHint: qualityLabel,
            codecLabelHint: codecLabel,
            resolvePayload: {
                ExternalStreamPayload(
                    mediaID: mediaID,
                    streamURL: streamURL,
                    title: title,
                    artist: artist,
                    artworkURL: artworkURL,
                    service: service,
                    qualityLabel: qualityLabel,
                    codecLabel: codecLabel
                )
            }
        )

        loadExternalTrack(immediateTrack, preserveQueue: false)
    }
}
