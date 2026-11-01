//
//  MultiSourceResolutionTests.swift
//  PlaybackCoreTests
//
//  Phase 4: more than one provider can contribute to a playback request, and the one that plays is
//  the ranking's choice rather than the registry's order.
//
//  Every provider here is a stub. Nothing in these tests touches a network, and no number in them is
//  a measurement of a real service — the bitrates are fixtures chosen to be obviously different.
//

import Foundation
import Models
@testable import PlaybackCore
import ProviderSDK
import Testing

// MARK: - Builders

private func stream(
    _ path: String,
    mime: String? = "audio/mp4",
    bitrate: Int? = nil,
    kind: SourceStream.Kind = .direct
) -> SourceStream {
    SourceStream(
        url: URL(string: "https://cdn.example.com/\(path)")!,
        kind: kind,
        mimeType: mime,
        bitrate: bitrate
    )
}

private func track(
    _ id: String,
    title: String = "Ivy",
    artist: String = "Frank Ocean",
    duration: Double = 249
) -> SourceTrack {
    SourceTrack(id: id, title: title, artist: artist, durationSeconds: duration)
}

/// A `SongSource` row. `cachedAt` also provides a still-fresh cached URL, so it can stand in for a
/// warm representation as well as a cold one.
@MainActor
private func binding(sourceID: String, trackID: String, cachedAt: Date? = nil) -> SongSource {
    let source = SongSource(sourceID: sourceID, sourceTrackID: trackID)
    if let cachedAt {
        source.cacheStream(
            url: URL(string: "https://cdn.example.com/cached-\(sourceID).m4a")!,
            mimeType: "audio/mp4",
            expiresAt: cachedAt.addingTimeInterval(3600),
            now: cachedAt
        )
    }
    return source
}

private func requestedRef(
    sourceID: String = "youtube_music",
    trackID: String = "v1",
    songID: String? = "song-1"
) -> PlayableRef {
    PlayableRef(
        songID: songID,
        sourceID: sourceID,
        sourceTrackID: trackID,
        title: "Ivy",
        artist: "Frank Ocean",
        durationSeconds: 249
    )
}

private enum StubError: Error {
    case refused
    case signedURLFailure(String)
}

/// A provider that returns exactly what the test gives it and records what it was asked.
private actor StubProvider: MusicSource {
    nonisolated let id: String
    nonisolated let capabilities: SourceCapability
    nonisolated var displayName: String {
        id
    }

    private let streamsByTrackID: [String: [SourceStream]]
    private let searchResults: [SourceTrack]
    private let streamDelay: Duration
    private let searchDelay: Duration
    private let failure: (any Error)?

    private(set) var streamRequests: [String] = []
    private(set) var searchRequests: [String] = []

    init(
        id: String,
        capabilities: SourceCapability = [.search, .stream],
        streams: [String: [SourceStream]] = [:],
        searchResults: [SourceTrack] = [],
        streamDelay: Duration = .zero,
        searchDelay: Duration = .zero,
        failure: (any Error)? = nil
    ) {
        self.id = id
        self.capabilities = capabilities
        self.streamsByTrackID = streams
        self.searchResults = searchResults
        self.streamDelay = streamDelay
        self.searchDelay = searchDelay
        self.failure = failure
    }

    func searchTracks(query: String, limit _: Int) async throws -> [SourceTrack] {
        searchRequests.append(query)
        if searchDelay > .zero {
            try await Task.sleep(for: searchDelay)
        }
        return searchResults
    }

    func stream(trackID: String, quality _: QualityHint) async throws -> SourceStream {
        let streams = try await streamCandidates(trackID: trackID, quality: .high)
        guard let first = streams.first else {
            throw SourceError.noStreamAvailable(source: id, trackID: trackID)
        }
        return first
    }

    func streamCandidates(trackID: String, quality _: QualityHint) async throws -> [SourceStream] {
        streamRequests.append(trackID)
        if streamDelay > .zero {
            try await Task.sleep(for: streamDelay)
        }
        if let failure {
            throw failure
        }
        return streamsByTrackID[trackID] ?? []
    }
}

/// The YouTube-ish provider: one 128 kbps AAC audio-only stream.
private func lowQualityProvider(
    id: String = "youtube_music",
    trackID: String = "v1",
    delay: Duration = .zero
) -> StubProvider {
    StubProvider(
        id: id,
        streams: [trackID: [stream("low.m4a", bitrate: 128_000)]],
        streamDelay: delay
    )
}

/// A plugin-ish provider: one lossless FLAC stream with reported depth and rate.
private func highQualityProvider(
    id: String = "tidal",
    trackID: String = "t-9",
    delay: Duration = .zero
) -> StubProvider {
    StubProvider(
        id: id,
        streams: [trackID: [
            SourceStream(
                url: URL(string: "https://cdn.example.com/high.flac")!,
                kind: .direct,
                mimeType: "audio/flac",
                bitrate: 1_411_200,
                bitDepth: 16,
                sampleRate: 44100
            ),
        ]],
        streamDelay: delay
    )
}

// MARK: - Stage A: providers cisum already knows

@MainActor
@Suite("Multi-provider selection from stored representations")
struct MultiProviderCandidateTests {
    private func resolver(
        _ sources: [any MusicSource],
        bindings: [SongSource],
        budget: ResolutionBudget = ResolutionBudget(improvementWindow: .seconds(2))
    ) -> PlaybackResolver {
        let resolver = PlaybackResolver(sources: SourceRegistry(sources: sources), budget: budget)
        resolver.bindings = { _ in bindings }
        return resolver
    }

    /// The central claim of this pass: a better stream for the *same recording* on a provider further
    /// down the registry wins over the requested provider's stream.
    @Test("a higher-quality provider wins over the requested provider")
    func betterProviderWins() async throws {
        let resolver = resolver(
            [lowQualityProvider(), highQualityProvider()],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")]
        )

        let ranked = try await resolver.resolve(requestedRef())

        #expect(ranked.first?.sourceID == "tidal")
        #expect(ranked.first?.stream.mimeType == "audio/flac")
        #expect(ranked.first?.stream.bitrate == 1_411_200)
        // The losing provider's candidate is still there as a fallback.
        #expect(ranked.count == 2)
        #expect(ranked.last?.sourceID == "youtube_music")
    }

    @Test("registry order does not decide the winner")
    func orderIndependent() async throws {
        let bindings = [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")]

        let forward = try await resolver([lowQualityProvider(), highQualityProvider()], bindings: bindings)
            .resolve(requestedRef())
        let reversedResolver = resolver([highQualityProvider(), lowQualityProvider()], bindings: Array(bindings.reversed()))
        let reversed = try await reversedResolver.resolve(requestedRef())

        #expect(forward.first?.sourceID == "tidal")
        #expect(reversed.first?.sourceID == "tidal")
        #expect(forward.first?.stream.url == reversed.first?.stream.url)
    }

    /// Equality is decided by the tie-break, and the tie-break is the source the user asked for —
    /// not the order the registry happened to list.
    @Test("equal candidates fall to the requested provider")
    func tieGoesToRequestedProvider() async throws {
        let youtube = StubProvider(id: "youtube_music", streams: ["v1": [stream("yt.m4a", bitrate: 128_000)]])
        let plugin = StubProvider(id: "tidal", streams: ["t-9": [stream("tidal.m4a", bitrate: 128_000)]])
        let resolver = resolver(
            [plugin, youtube],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")]
        )

        let ranked = try await resolver.resolve(requestedRef())
        #expect(ranked.first?.sourceID == "youtube_music")
        #expect(ranked.first?.sourceOrder == 0)
    }

    @Test("a provider that throws is skipped, and the rest still play")
    func failedProviderIsSkipped() async throws {
        let broken = StubProvider(id: "tidal", failure: StubError.refused)
        let resolver = resolver(
            [lowQualityProvider(), broken],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")]
        )

        let ranked = try await resolver.resolve(requestedRef())
        #expect(ranked.count == 1)
        #expect(ranked.first?.sourceID == "youtube_music")
    }

    /// A provider that has not answered inside the budget is abandoned; playback does not wait for it.
    @Test("a slow provider does not hold up playback")
    func slowProviderIsAbandoned() async throws {
        let slow = highQualityProvider(delay: .seconds(5))
        let resolver = resolver(
            [lowQualityProvider(), slow],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")],
            budget: ResolutionBudget(improvementWindow: .milliseconds(50))
        )

        let start = ContinuousClock.now
        let ranked = try await resolver.resolve(requestedRef())
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(ranked.count == 1)
        #expect(ranked.first?.sourceID == "youtube_music")
        // The stub honours cancellation, so this is the window itself, not five seconds. The bound is
        // generous so the test measures the behaviour rather than the machine.
        #expect(elapsed < .seconds(2))
    }

    /// A single stream-capable provider is the configuration cisum actually ships today, and its
    /// latency is not a fault. Once resolution abandoned a provider that took longer than the
    /// improvement window, a working YouTube resolve became "Could not find this track".
    @Test("a sole provider slower than the improvement window still plays")
    func soleSlowProviderStillPlays() async throws {
        let slow = lowQualityProvider(delay: .milliseconds(300))
        let resolver = resolver(
            [slow],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1")],
            budget: ResolutionBudget(improvementWindow: .milliseconds(20), firstCandidateTimeout: .seconds(5))
        )

        let ranked = try await resolver.resolve(requestedRef())

        #expect(ranked.count == 1)
        #expect(ranked.first?.sourceID == "youtube_music")
    }

    /// "The only candidate" is not the same claim as "the candidate that matched", and selecting it
    /// is a deliberate decision rather than an oversight: refusing to play a track cisum cannot
    /// positively identify would make an ad-hoc play of a search result impossible, which is worse
    /// than playing it with the identity recorded as unconfirmed. What must not happen is the two
    /// being reported as if they were the same thing — which is why the resolver logs the difference.
    @Test("a sole candidate with no identity evidence is played, with its uncertainty recorded")
    func soleUnconfirmedCandidateIsPlayed() async throws {
        // No stored representation and no canonical song: the user's tap is all the evidence there is.
        let resolver = resolver([lowQualityProvider()], bindings: [])

        let ranked = try await resolver.resolve(requestedRef(songID: nil))

        #expect(ranked.count == 1)
        #expect(ranked.first?.identity == .unconfirmed)
        #expect(!ranked.isEmpty)
    }

    /// Stage A is the "no search" stage. Resolving by a stored id is one HTTP call; a search is many,
    /// and the architecture's whole promise is that a known track is never searched for again.
    @Test("no provider is searched while a stored id exists")
    func noSearchWhenAnIDIsKnown() async throws {
        let provider = StubProvider(
            id: "tidal",
            streams: ["t-9": [stream("t.m4a", bitrate: 256_000)]],
            searchResults: [track("t-9")]
        )
        let resolver = resolver([provider], bindings: [binding(sourceID: "tidal", trackID: "t-9")])

        let ranked = try await resolver.resolve(requestedRef(sourceID: "tidal", trackID: "t-9"))

        #expect(ranked.count == 1)
        let searches = await provider.searchRequests
        let streamRequests = await provider.streamRequests
        #expect(searches.isEmpty)
        #expect(streamRequests == ["t-9"])
    }

    /// A representation on a service cisum cannot stream from is identity evidence, not a transport.
    @Test("a metadata-only provider is never asked to stream")
    func nonStreamCapableProviderIsNotAsked() async throws {
        let spotify = StubProvider(id: "spotify", capabilities: [.search])
        let resolver = resolver(
            [lowQualityProvider(), spotify],
            bindings: [binding(sourceID: "spotify", trackID: "sp-1"), binding(sourceID: "youtube_music", trackID: "v1")]
        )

        let ranked = try await resolver.resolve(requestedRef())

        #expect(ranked.first?.sourceID == "youtube_music")
        let streamRequests = await spotify.streamRequests
        #expect(streamRequests.isEmpty)
    }

    /// The warm path must keep working *across* providers: the binding that gets the URL cached is the
    /// one that played, not the one the ref named.
    @Test("the winner is persisted against its own provider binding")
    func persistsAgainstSelectedProvider() async throws {
        let resolver = resolver(
            [lowQualityProvider(), highQualityProvider()],
            bindings: [binding(sourceID: "youtube_music", trackID: "v1"), binding(sourceID: "tidal", trackID: "t-9")]
        )
        var persisted: [(source: String, track: String)] = []
        resolver.persist = { ref, track, _ in persisted.append((ref.sourceID, track.id)) }

        let ranked = try await resolver.resolve(requestedRef())

        #expect(ranked.first?.sourceID == "tidal")
        #expect(persisted.count == 1)
        #expect(persisted.first?.source == "tidal")
        #expect(persisted.first?.track == "t-9")
    }

    @Test("the warm path replays the most recently resolved representation")
    func warmPathPrefersTheMostRecentChoice() async throws {
        // Both are still fresh, so there is nothing to rank: the last stream the ranker *chose* is the
        // only evidence of which of them is the better one.
        let older = binding(sourceID: "youtube_music", trackID: "v1", cachedAt: Date().addingTimeInterval(-120))
        let newer = binding(sourceID: "tidal", trackID: "t-9", cachedAt: Date().addingTimeInterval(-10))
        let resolver = resolver([lowQualityProvider(), highQualityProvider()], bindings: [older, newer])

        let ranked = try await resolver.resolve(requestedRef())

        #expect(ranked.count == 1)
        #expect(ranked.first?.sourceID == "tidal")
        #expect(ranked.first?.stream.url.lastPathComponent == "cached-tidal.m4a")
        #expect(ranked.first?.identity == .confirmed(.establishedBinding))
    }

    @Test("the requested provider wins the warm race when both were resolved together")
    func warmTieGoesToRequestedProvider() async throws {
        let when = Date().addingTimeInterval(-30)
        let resolver = resolver(
            [lowQualityProvider(), highQualityProvider()],
            bindings: [
                binding(sourceID: "youtube_music", trackID: "v1", cachedAt: when),
                binding(sourceID: "tidal", trackID: "t-9", cachedAt: when),
            ]
        )

        let ranked = try await resolver.resolve(requestedRef())
        #expect(ranked.first?.sourceID == "youtube_music")
    }
}

// MARK: - Stage B: providers that have to be searched

@MainActor
@Suite("Multi-provider selection by search")
struct MultiProviderSearchTests {
    private func resolver(
        _ sources: [any MusicSource],
        budget: ResolutionBudget = ResolutionBudget(improvementWindow: .seconds(2))
    ) -> PlaybackResolver {
        let resolver = PlaybackResolver(sources: SourceRegistry(sources: sources), budget: budget)
        resolver.bindings = { _ in [] }
        return resolver
    }

    /// A Spotify-style ref: identified by a service that cannot stream, with no stored representation
    /// anywhere. Both providers are searched, and the better of the two matches wins.
    private func metadataOnlyRef() -> PlayableRef {
        PlayableRef(
            songID: nil,
            sourceID: "spotify",
            sourceTrackID: "sp-1",
            title: "Ivy",
            artist: "Frank Ocean",
            durationSeconds: 249
        )
    }

    @Test("searching every provider lets the better match win")
    func searchSpansProviders() async throws {
        let youtube = StubProvider(
            id: "youtube_music",
            streams: ["vid1": [stream("yt.m4a", bitrate: 128_000)]],
            searchResults: [track("vid1")]
        )
        let plugin = try StubProvider(
            id: "tidal",
            streams: ["t-9": [SourceStream(
                url: #require(URL(string: "https://cdn.example.com/high.flac")),
                kind: .direct,
                mimeType: "audio/flac",
                bitrate: 1_411_200,
                bitDepth: 16,
                sampleRate: 44100
            )]],
            searchResults: [track("t-9")]
        )

        let ranked = try await resolver([youtube, plugin]).resolve(metadataOnlyRef())

        #expect(ranked.first?.sourceID == "tidal")
        let youtubeSearches = await youtube.searchRequests
        let pluginSearches = await plugin.searchRequests
        #expect(youtubeSearches.count == 1)
        #expect(pluginSearches.count == 1)
    }

    /// Identity outranks quality: a provider offering a *different performance* of the right song
    /// contributes nothing, however good its numbers look.
    @Test("a different version is not a candidate, whatever it claims")
    func wrongVersionIsNotACandidate() async throws {
        let live = StubProvider(
            id: "tidal",
            streams: ["live-9": [stream("live.flac", mime: "audio/flac", bitrate: 1_411_200)]],
            searchResults: [track("live-9", title: "Ivy (Live at Coachella)")]
        )
        let youtube = StubProvider(
            id: "youtube_music",
            streams: ["vid1": [stream("yt.m4a", bitrate: 128_000)]],
            searchResults: [track("vid1")]
        )

        let ranked = try await resolver([youtube, live]).resolve(metadataOnlyRef())

        #expect(ranked.first?.sourceID == "youtube_music")
        #expect(!ranked.contains { $0.stream.url.lastPathComponent == "live.flac" })
    }

    @Test("a provider with no acceptable match simply does not contribute")
    func unmatchedProviderContributesNothing() async throws {
        let unrelated = StubProvider(
            id: "tidal",
            streams: ["x-1": [stream("unrelated.flac", mime: "audio/flac", bitrate: 1_411_200)]],
            searchResults: [track("x-1", title: "Pyramids", artist: "Someone Else")]
        )
        let youtube = StubProvider(
            id: "youtube_music",
            streams: ["vid1": [stream("yt.m4a", bitrate: 128_000)]],
            searchResults: [track("vid1")]
        )

        let ranked = try await resolver([youtube, unrelated]).resolve(metadataOnlyRef())

        #expect(ranked.count == 1)
        #expect(ranked.first?.sourceID == "youtube_music")
    }

    @Test("a slow search is abandoned rather than waited on")
    func slowSearchIsAbandoned() async throws {
        let slow = StubProvider(
            id: "tidal",
            streams: ["t-9": [stream("high.flac", mime: "audio/flac", bitrate: 1_411_200)]],
            searchResults: [track("t-9")],
            searchDelay: .seconds(5)
        )
        let fast = StubProvider(
            id: "youtube_music",
            streams: ["vid1": [stream("yt.m4a", bitrate: 128_000)]],
            searchResults: [track("vid1")]
        )

        let ranked = try await resolver([fast, slow], budget: ResolutionBudget(improvementWindow: .milliseconds(80)))
            .resolve(metadataOnlyRef())

        #expect(ranked.first?.sourceID == "youtube_music")
    }

    @Test("nothing playable anywhere still fails, with the provider reason classified")
    func totalFailureIsClassified() async throws {
        let broken = StubProvider(id: "youtube_music", searchResults: [track("vid1")], failure: StubError.refused)
        let resolver = resolver([broken])

        await #expect(throws: ResolutionError.self) {
            _ = try await resolver.resolve(metadataOnlyRef())
        }
    }
}

// MARK: - The collection primitive itself

@Suite("Bounded provider collection")
struct CandidateCollectionTests {
    private func job(_ id: String, order: Int, work: @escaping @Sendable () async throws -> SourceStreams?) -> SourceResolveJob {
        SourceResolveJob(sourceID: id, order: order, work: work)
    }

    private func contribution(_ path: String) -> SourceStreams {
        SourceStreams(trackID: "t", streams: [stream(path)], identity: .unconfirmed)
    }

    @Test("reports come back in the caller's order, not completion order")
    func reportsAreOrdered() async {
        let jobs = [
            job("slow", order: 0) { try await Task.sleep(for: .milliseconds(30)); return contribution("a") },
            job("fast", order: 1) { contribution("b") },
        ]

        let reports = await CandidateCollection.collect(jobs, within: ResolutionBudget(improvementWindow: .seconds(2)))

        #expect(reports.map(\.sourceID) == ["slow", "fast"])
        #expect(reports.allSatisfy { $0.streams != nil })
    }

    @Test("a provider that never answers is reported as timed out, and the others are not affected")
    func timeoutIsReported() async {
        let jobs = [
            job("fast", order: 0) { contribution("a") },
            job("stuck", order: 1) { try await Task.sleep(for: .seconds(5)); return nil },
        ]

        let reports = await CandidateCollection.collect(jobs, within: ResolutionBudget(improvementWindow: .milliseconds(40)))

        #expect(reports.first?.result == .answered(contribution("a")))
        #expect(reports.last?.result == .timedOut)
    }

    /// The regression this pass exists for. A provider slower than the improvement window is not a
    /// broken provider: while nothing is playing, the request waits for it instead of throwing the
    /// only stream cisum could have played away and reporting the track as unplayable.
    @Test("a slow provider is not abandoned while nothing is playing yet")
    func slowSoleProviderIsWaitedFor() async {
        let jobs = [
            job("slow", order: 0) { try await Task.sleep(for: .milliseconds(250)); return contribution("a") },
        ]

        let reports = await CandidateCollection.collect(
            jobs,
            within: ResolutionBudget(improvementWindow: .milliseconds(20), firstCandidateTimeout: .seconds(5))
        )

        #expect(reports.map(\.result) == [.answered(contribution("a"))])
        #expect(reports.first?.hasUsableStreams == true)
    }

    /// The improvement window starts when the *first candidate arrives*, not when the request does,
    /// so a second provider is neither cut off before the first has answered nor waited on forever
    /// afterwards.
    @Test("the improvement window is measured from the first candidate")
    func improvementWindowStartsAtTheFirstCandidate() async {
        let jobs = [
            job("fast", order: 0) { contribution("a") },
            job("later", order: 1) { try await Task.sleep(for: .milliseconds(120)); return contribution("b") },
        ]

        let reports = await CandidateCollection.collect(
            jobs,
            within: ResolutionBudget(improvementWindow: .milliseconds(400), firstCandidateTimeout: .milliseconds(50))
        )

        #expect(reports.map(\.result) == [.answered(contribution("a")), .answered(contribution("b"))])
    }

    /// An answer of "I have nothing" is not a candidate. It must not close the window that exists to
    /// obtain the first one — the empty provider answering first is exactly the case where a second
    /// provider's slow answer is the only stream cisum will get.
    @Test("an empty answer does not close the window for the first candidate")
    func emptyAnswerDoesNotEndTheWait() async {
        let jobs = [
            job("empty", order: 0) { SourceStreams(trackID: "t", streams: [], identity: .unconfirmed) },
            job("answering", order: 1) { try await Task.sleep(for: .milliseconds(250)); return contribution("a") },
        ]

        let reports = await CandidateCollection.collect(
            jobs,
            within: ResolutionBudget(improvementWindow: .milliseconds(20), firstCandidateTimeout: .seconds(5))
        )

        #expect(reports.first?.hasUsableStreams == false)
        #expect(reports.last?.result == .answered(contribution("a")))
    }

    /// With no candidate at all, waiting is not unbounded: the backstop ends the request so a
    /// provider that never returns cannot leave the user watching a spinner.
    @Test("a request with nothing playable still gives up at the backstop")
    func backstopEndsAHopelessRequest() async {
        let jobs = [job("never", order: 0) { try await Task.sleep(for: .seconds(5)); return nil }]

        let start = ContinuousClock.now
        let reports = await CandidateCollection.collect(
            jobs,
            within: ResolutionBudget(firstCandidateTimeout: .milliseconds(80))
        )
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(reports.map(\.result) == [.timedOut])
        #expect(elapsed < .seconds(2))
    }

    @Test("a provider with nothing to offer is not a failure")
    func nothingIsNotAFailure() async {
        let jobs = [job("empty", order: 0) { nil }]

        let reports = await CandidateCollection.collect(jobs, within: .default)

        #expect(reports.first?.result == .nothing)
        #expect(reports.first?.streams == nil)
    }

    /// The reason is the error's *type*, never its message: a provider error message routinely embeds
    /// the URL it failed on, and the URL is a credential until it expires.
    @Test("a failure reason cannot carry a provider message")
    func failureReasonIsTheTypeOnly() async {
        let jobs = [
            job("provider", order: 0) {
                throw StubError.signedURLFailure("https://cdn.example.com/audio?token=SECRET")
            },
        ]

        let reports = await CandidateCollection.collect(jobs, within: .default)

        guard case let .failed(reason) = reports.first?.result else {
            Issue.record("expected a failure, got \(String(describing: reports.first?.result))")
            return
        }
        #expect(reason == "StubError")
        #expect(!reason.contains("http"))
        #expect(!reason.contains("SECRET"))
    }

    @Test("no jobs means no work")
    func emptyJobList() async {
        let reports = await CandidateCollection.collect([], within: .default)
        #expect(reports.isEmpty)
    }
}

// MARK: - Source trust

@Suite("Source trust policy")
struct SourceTrustPolicyTests {
    @Test("a provider cisum ships is first-party")
    func nativeIsFirstParty() {
        #expect(SourceTrustPolicy.trust(for: "youtube_music", isRegistered: true) == .firstParty)
        #expect(SourceTrustPolicy.trust(for: "youtube", isRegistered: true) == .firstParty)
    }

    @Test("a registered provider cisum did not ship is third-party")
    func pluginIsThirdParty() {
        #expect(SourceTrustPolicy.trust(for: "tidals-morgk", isRegistered: true) == .thirdParty)
    }

    /// An unregistered id is not "untrusted" — it is unknown, which is a different and more honest
    /// answer.
    @Test("an unregistered provider is unknown, not third-party")
    func unregisteredIsUnknown() {
        #expect(SourceTrustPolicy.trust(for: "ghost", isRegistered: false) == .unknown)
    }
}
