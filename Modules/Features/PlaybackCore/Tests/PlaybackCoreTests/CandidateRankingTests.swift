//
//  CandidateRankingTests.swift
//  PlaybackCoreTests
//
//  Phase 3: candidate ranking semantics, the resolver's use of them, the bounded fallback ladder,
//  and the active-stream diagnostic model.
//
//  The ranking tests assert the policy directly. The resolver tests assert the *production* path —
//  that the adapter's own order no longer decides what plays.
//

import Foundation
import Models
@testable import PlaybackCore
import ProviderSDK
import Testing

// MARK: - Builders

private func makeStream(
    path: String = "a",
    kind: SourceStream.Kind = .direct,
    mime: String? = nil,
    bitrate: Int? = nil,
    bitDepth: Int? = nil,
    sampleRate: Int? = nil,
    isCacheable: Bool = true
) -> SourceStream {
    SourceStream(
        url: URL(string: "https://cdn.example.com/\(path)")!,
        kind: kind,
        mimeType: mime,
        bitrate: bitrate,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
        isCacheable: isCacheable
    )
}

/// A candidate with everything defaulted, so each test states only the dimension it is about.
private func makeCandidate(
    _ stream: SourceStream,
    source: String = "youtube_music",
    track: String = "v1",
    identity: CandidateIdentity = .confirmed(.confidentMatch),
    availability: CandidateAvailability = .remote,
    eligibility: CandidateEligibility = .eligible,
    trust: SourceTrust = .firstParty,
    evidence: QualityEvidence = .advertised,
    latencyMs: Double? = nil,
    index: Int = 0
) -> PlaybackCandidate {
    PlaybackCandidate(
        stream: stream,
        sourceID: source,
        sourceTrackID: track,
        identity: identity,
        availability: availability,
        eligibility: eligibility,
        trust: trust,
        qualityEvidence: evidence,
        latencyMs: latencyMs,
        adapterIndex: index
    )
}

// MARK: - Ranking policy

@Suite("Candidate ranking — quality and evidence")
struct CandidateQualityRankingTests {
    private let policy = CandidateRankingPolicy()

    /// Positive control: an all-unknown candidate is still usable and still selectable. Missing
    /// metadata must reduce certainty without eliminating anything.
    @Test("unknown metadata never makes a candidate unusable, and never wins over known quality")
    func unknownIsUsableButNeverFabricated() throws {
        let unknown = makeCandidate(makeStream(path: "unknown"), index: 0)
        let known = makeCandidate(
            makeStream(path: "flac", mime: "audio/flac", bitDepth: 16, sampleRate: 44100),
            index: 1
        )

        #expect(unknown.evidence == .unknown)
        #expect(!unknown.hasStructuredQuality)

        #expect(try #require(policy.rank([unknown, known]).selected).stream.bitDepth == 16)
        // Same answer with the input order reversed.
        #expect(try #require(policy.rank([known, unknown]).selected).stream.bitDepth == 16)
        // And a lone unknown candidate is still selected rather than dropped.
        #expect(policy.rank([unknown]).selected?.adapterIndex == 0)
    }

    @Test("ranking is deterministic and independent of input order")
    func deterministicOrder() {
        let aac = makeCandidate(makeStream(path: "aac", mime: "audio/mp4", bitrate: 128_000), index: 0)
        let flac = makeCandidate(
            makeStream(path: "flac", mime: "audio/flac", bitDepth: 24, sampleRate: 96000),
            index: 1
        )
        let mp3 = makeCandidate(makeStream(path: "mp3", mime: "audio/mpeg", bitrate: 320_000), index: 2)

        let forward = policy.rank([aac, flac, mp3]).ranked.map(\.adapterIndex)
        let backward = policy.rank([mp3, flac, aac]).ranked.map(\.adapterIndex)
        #expect(forward == [1, 2, 0])
        #expect(forward == backward)
    }

    @Test("a lossless candidate beats a higher-bitrate lossy one")
    func losslessBeatsHighBitrateLossy() throws {
        let lossy = makeCandidate(makeStream(path: "mp3", mime: "audio/mpeg", bitrate: 320_000), index: 0)
        let lossless = makeCandidate(
            makeStream(path: "flac", mime: "audio/flac", bitDepth: 16, sampleRate: 44100),
            index: 1
        )

        #expect(try #require(policy.rank([lossy, lossless]).selected).stream.mimeType == "audio/flac")
    }

    /// Equal numbers, different provenance: the measured one wins. No producer measures anything
    /// yet, but the distinction has to exist before one can.
    @Test("at equal quality, measured evidence beats reported evidence")
    func verifiedBeatsAdvertised() throws {
        let advertised = makeCandidate(
            makeStream(path: "adv", mime: "audio/flac", bitDepth: 16, sampleRate: 44100),
            evidence: .advertised,
            index: 0
        )
        let verified = makeCandidate(
            makeStream(path: "ver", mime: "audio/flac", bitDepth: 16, sampleRate: 44100),
            evidence: .verified,
            index: 1
        )

        #expect(try #require(policy.rank([advertised, verified]).selected).adapterIndex == 1)
        #expect(try #require(policy.rank([verified, advertised]).selected).adapterIndex == 1)
    }

    /// A producer cannot manufacture evidence by declaring provenance while reporting nothing.
    @Test("declared provenance with no numbers is unknown evidence")
    func declarationWithoutNumbersIsUnknown() {
        let bare = makeCandidate(makeStream(path: "bare"), evidence: .verified, index: 0)
        #expect(bare.evidence == .unknown)
    }

    @Test("a codec-less candidate loses to a codec-comparable one, and a malformed one still ranks")
    func codecAwareComparison() {
        let none = makeCandidate(makeStream(path: "none"), index: 0)
        let aac = makeCandidate(makeStream(path: "aac", mime: "audio/mp4"), index: 1)
        let opus = makeCandidate(makeStream(path: "opus", mime: "audio/opus"), index: 2)

        let ranked = policy.rank([none, aac, opus]).ranked.map(\.adapterIndex)
        #expect(ranked == [2, 1, 0])

        // A candidate describing nothing at all is still ranked, not discarded.
        let malformed = makeCandidate(makeStream(path: "malformed", mime: "", bitrate: 0), index: 0)
        #expect(policy.rank([malformed]).selected != nil)
    }

    @Test("equal candidates keep the adapter's order")
    func equalCandidatesUseAdapterOrder() {
        let first = makeCandidate(makeStream(path: "x", mime: "audio/mp4", bitrate: 256_000), index: 0)
        let second = makeCandidate(makeStream(path: "y", mime: "audio/mp4", bitrate: 256_000), index: 1)

        #expect(policy.rank([second, first]).ranked.map(\.adapterIndex) == [0, 1])
    }
}

@Suite("Candidate ranking — identity is a gate")
struct CandidateIdentityGateTests {
    private let policy = CandidateRankingPolicy()

    /// The headline rule: a wrong recording does not become right by being higher quality.
    @Test("an incompatible recording cannot win on quality")
    func incompatibleCannotWinOnQuality() {
        let wrongButHires = makeCandidate(
            makeStream(path: "wrong", mime: "audio/flac", bitDepth: 24, sampleRate: 192_000),
            identity: .incompatible(reason: "live version"),
            index: 0
        )
        let rightButModest = makeCandidate(makeStream(path: "right", mime: "audio/mp4"), index: 1)

        let result = policy.rank([wrongButHires, rightButModest])
        #expect(result.selected?.adapterIndex == 1)
        #expect(result.rejected.count == 1)
        #expect(result.rejected.first?.reason == .incompatibleRecording("live version"))
    }

    @Test("stronger identity evidence outranks weaker, before quality is considered")
    func identityTiersOrder() {
        let weak = makeCandidate(makeStream(path: "weak", mime: "audio/flac", bitDepth: 24), identity: .unconfirmed, index: 0)
        let strong = makeCandidate(makeStream(path: "strong"), identity: .confirmed(.establishedBinding), index: 1)

        let ranked = policy.rank([weak, strong]).ranked
        #expect(ranked.map(\.adapterIndex) == [1, 0])
        #expect(ranked.first?.identity == .confirmed(.establishedBinding))
    }

    @Test("an explicit version conflict is rejected before eligibility is even checked")
    func conflictRejectedRegardlessOfEligibility() {
        let conflicting = makeCandidate(makeStream(path: "c"), identity: .incompatible(reason: "remix"), index: 0)
        let result = policy.rank([conflicting])
        #expect(result.ranked.isEmpty)
        #expect(result.selected == nil)
        #expect(result.rejected.first?.reason == .incompatibleRecording("remix"))
    }
}

@Suite("Candidate ranking — eligibility, locality, trust, latency")
struct CandidateContextRankingTests {
    /// An unplayable candidate is refused, and says why — it is not silently ranked last.
    @Test("an ineligible candidate is rejected, never ranked")
    func ineligibleIsRejected() {
        let drm = makeCandidate(
            makeStream(path: "drm", mime: "audio/flac", bitDepth: 24),
            eligibility: .ineligible(reason: "needs DRM key"),
            index: 0
        )
        let plain = makeCandidate(makeStream(path: "plain", mime: "audio/mp4"), index: 1)

        let result = CandidateRankingPolicy().rank([drm, plain])
        #expect(result.selected?.adapterIndex == 1)
        #expect(result.rejected.first?.reason == .ineligible("needs DRM key"))
    }

    /// Local media is preferred **within the same recording**, which is the case the policy is for.
    @Test("a local candidate wins when the recording is equally established")
    func localPreferredWithinSameRecording() throws {
        let remote = makeCandidate(makeStream(path: "remote", mime: "audio/flac", bitDepth: 24, sampleRate: 96000), availability: .remote, index: 0)
        let local = makeCandidate(makeStream(path: "local", mime: "audio/mp4", bitrate: 256_000), availability: .local, index: 1)

        #expect(try #require(CandidateRankingPolicy().rank([remote, local]).selected).availability == .local)
    }

    /// …and it is *not* preferred across recordings. Preferring local must never surface an
    /// unrelated file over a confidently matched stream.
    @Test("a local candidate does not outrank a confident match for a different identity")
    func localDoesNotOverrideIdentity() throws {
        let localUnconfirmed = makeCandidate(makeStream(path: "local"), identity: .unconfirmed, availability: .local, index: 0)
        let remoteConfirmed = makeCandidate(makeStream(path: "remote"), identity: .confirmed(.exactISRC), availability: .remote, index: 1)

        #expect(try #require(CandidateRankingPolicy().rank([localUnconfirmed, remoteConfirmed]).selected).availability == .remote)
    }

    @Test("local preference can be switched off")
    func localPreferenceIsConfigurable() throws {
        let remote = makeCandidate(makeStream(path: "remote"), availability: .remote, index: 0)
        let local = makeCandidate(makeStream(path: "local"), availability: .local, index: 1)

        let policy = CandidateRankingPolicy(prefersLocal: false)
        #expect(try #require(policy.rank([local, remote]).selected).adapterIndex == 0)
    }

    @Test("a trusted source wins at equal quality")
    func trustTieBreak() throws {
        let plugin = makeCandidate(makeStream(path: "plugin", mime: "audio/mp4", bitrate: 256_000), source: "someplugin", trust: .thirdParty, index: 0)
        let native = makeCandidate(makeStream(path: "native", mime: "audio/mp4", bitrate: 256_000), source: "youtube_music", trust: .firstParty, index: 1)

        #expect(try #require(CandidateRankingPolicy().rank([plugin, native]).selected).sourceID == "youtube_music")
    }

    /// Unknown latency is neutral. It must not be treated as infinitely slow.
    @Test("latency is compared only when both candidates report it")
    func latencyTieBreak() throws {
        let unknownFirst = makeCandidate(makeStream(path: "u", mime: "audio/mp4", bitrate: 256_000), latencyMs: nil, index: 0)
        let measured = makeCandidate(makeStream(path: "m", mime: "audio/mp4", bitrate: 256_000), latencyMs: 40, index: 1)

        // Falls through to adapter order: the unknown one keeps its place, it is not punished.
        #expect(try #require(CandidateRankingPolicy().rank([unknownFirst, measured]).selected).adapterIndex == 0)

        // With both known, the faster one wins.
        let slow = makeCandidate(makeStream(path: "s", mime: "audio/mp4", bitrate: 256_000), latencyMs: 900, index: 1)
        let fast = makeCandidate(makeStream(path: "f", mime: "audio/mp4", bitrate: 256_000), latencyMs: 30, index: 0)
        #expect(try #require(CandidateRankingPolicy().rank([slow, fast]).selected).adapterIndex == 0)
    }

    /// A muxed container's bitrate covers video as well as audio, so it is not audio-quality
    /// evidence and must not decide a comparison.
    @Test("a muxed video candidate cannot win on its bitrate")
    func muxedBitrateIsNotAudioQuality() throws {
        let muxed = makeCandidate(
            makeStream(path: "muxed", mime: "video/mp4", bitrate: 1_500_000),
            index: 0
        )
        let audioOnly = makeCandidate(makeStream(path: "audio", mime: "audio/mp4", bitrate: 128_000), index: 1)

        #expect(muxed.transportClass == .muxedVideo)
        #expect(!muxed.hasStructuredQuality, "a muxed bitrate is not audio-quality evidence")
        let selected = try #require(CandidateRankingPolicy().rank([muxed, audioOnly]).selected)
        #expect(selected.transportClass == .progressiveAudio)
    }

    @Test("progressive audio is preferred over an adaptive manifest at equal quality")
    func adaptiveManifestLosesToProgressive() {
        let hls = makeCandidate(makeStream(path: "hls", kind: .hls, mime: "application/x-mpegURL"), index: 0)
        let direct = makeCandidate(makeStream(path: "direct", mime: "audio/mp4"), index: 1)

        let ranked = CandidateRankingPolicy().rank([hls, direct]).ranked
        #expect(ranked.map(\.adapterIndex) == [1, 0])
        #expect(ranked.last?.transportClass == .adaptiveManifest)
    }
}

// MARK: - The resolver's production use of the ranking

/// A source that returns exactly the streams it was given, in the order it was given.
private struct FixedStreamSource: MusicSource {
    let id: String
    let streams: [SourceStream]

    var displayName: String {
        id
    }

    var capabilities: SourceCapability {
        [.stream]
    }

    func searchTracks(query _: String, limit _: Int) async throws -> [SourceTrack] {
        []
    }

    func stream(trackID _: String, quality _: QualityHint) async throws -> SourceStream {
        guard let first = streams.first else {
            throw SourceError.unsupported(source: id, operation: "stream")
        }
        return first
    }

    func streamCandidates(trackID _: String, quality _: QualityHint) async throws -> [SourceStream] {
        streams
    }
}

@MainActor
@Suite("Resolver uses the ranking (production path)")
struct PlaybackResolverRankingTests {
    private func ref() -> PlayableRef {
        PlayableRef(
            songID: "s",
            sourceID: "youtube_music",
            sourceTrackID: "v1",
            title: "Ivy",
            artist: "Frank Ocean",
            durationSeconds: 249
        )
    }

    /// Exactly what `YouTubeMusicSource.streamCandidates` returns today: the HLS manifest first,
    /// then the adaptive audio file, then the muxed download. Ranking must not accept that order.
    private func youTubeOrderedStreams() -> [SourceStream] {
        [
            makeStream(path: "hls.m3u8", kind: .hls, mime: "application/x-mpegURL"),
            makeStream(path: "audio.m4a", kind: .direct, mime: "audio/mp4", bitrate: 128_000),
            makeStream(path: "muxed.mp4", kind: .direct, mime: "video/mp4"),
        ]
    }

    private func resolver(streams: [SourceStream]) -> PlaybackResolver {
        let source = FixedStreamSource(id: "youtube_music", streams: streams)
        let resolver = PlaybackResolver(sources: SourceRegistry(sources: [source]))
        resolver.bindings = { _ in [] }
        return resolver
    }

    @Test("the advertised first stream is not what plays when ranking prefers another")
    func rankedSelectionBeatsAdapterOrder() async throws {
        let resolved = try await resolver(streams: youTubeOrderedStreams()).resolve(ref())

        #expect(resolved.count == 3)
        let selected = try #require(resolved.first)
        #expect(selected.transportClass == .progressiveAudio)
        #expect(selected.stream.mimeType == "audio/mp4")
        // The adapter's HLS-first order survives only as the last fallback.
        #expect(resolved.last?.transportClass == .adaptiveManifest)
    }

    @Test("reversing the adapter's array does not change what is selected")
    func selectionIsOrderIndependent() async throws {
        let forward = try await resolver(streams: youTubeOrderedStreams()).resolve(ref())
        let reversed = try await resolver(streams: youTubeOrderedStreams().reversed()).resolve(ref())

        #expect(forward.first?.stream.mimeType == reversed.first?.stream.mimeType)
        #expect(forward.first?.stream.url == reversed.first?.stream.url)
    }


    /// The binding must cache the URL that will actually play, or the warm path would hand back the
    /// candidate ranking already rejected.
    @Test("the selected stream is the one persisted, not the adapter's first")
    func persistsSelectedStream() async throws {
        let resolver = resolver(streams: youTubeOrderedStreams())
        var persisted: [String] = []
        resolver.persist = { _, _, stream in persisted.append(stream.url.lastPathComponent) }

        _ = try await resolver.resolve(ref())
        #expect(persisted == ["audio.m4a"])
    }

    @Test("a warm cached binding is unchanged, and its identity is the established binding")
    func warmPathUnchanged() async throws {
        let binding = SongSource(sourceID: "youtube_music", sourceTrackID: "v1")
        try binding.cacheStream(
            url: #require(URL(string: "https://cdn.example.com/cached.m4a")),
            mimeType: "audio/mp4",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let resolver = resolver(streams: youTubeOrderedStreams())
        resolver.bindings = { _ in [binding] }

        let resolved = try await resolver.resolve(ref())
        #expect(resolved.count == 1)
        #expect(resolved.first?.stream.url.lastPathComponent == "cached.m4a")
        #expect(resolved.first?.identity == .confirmed(.establishedBinding))
    }

    @Test("an ad-hoc play resolves as unconfirmed identity, and still plays")
    func adHocPlayIsUnconfirmed() async throws {
        let resolver = resolver(streams: youTubeOrderedStreams())
        let adHoc = PlayableRef(
            songID: nil,
            sourceID: "youtube_music",
            sourceTrackID: "v1",
            title: "Ivy",
            artist: "Frank Ocean"
        )

        let resolved = try await resolver.resolve(adHoc)
        #expect(resolved.first?.identity == .unconfirmed)
        #expect(resolved.first?.stream.mimeType == "audio/mp4")
    }

    @Test("a native source is ranked as first-party")
    func trustReachesRanking() async throws {
        let resolved = try await resolver(streams: youTubeOrderedStreams()).resolve(ref())
        #expect(resolved.first?.trust == .firstParty)
    }
}

// MARK: - Fallback ladder

@Suite("Fallback ladder")
struct FallbackLadderTests {
    private func candidates(_ count: Int) -> [PlaybackCandidate] {
        (0 ..< count).map { index in
            makeCandidate(makeStream(path: "s\(index)"), index: index)
        }
    }

    @Test("fallbacks are consumed in ranked order, then stop")
    func consumesInRankedOrder() {
        var ladder = FallbackLadder(candidates: candidates(3))
        #expect(ladder.startedFrom?.adapterIndex == 0)
        #expect(ladder.next()?.adapterIndex == 1)
        #expect(ladder.next()?.adapterIndex == 2)
        #expect(ladder.next() == nil)
        #expect(ladder.remainingCount == 0)
    }

    /// The termination property: exactly one fresh resolve per failure episode, no matter how many
    /// times the resolve is replaced. This is the bound that was missing before.
    @Test("a fresh resolve is permitted once and cannot re-arm itself")
    func resolveRetryIsBounded() {
        var ladder = FallbackLadder(candidates: candidates(2))

        #expect(ladder.next()?.adapterIndex == 1)
        #expect(ladder.next() == nil)

        let retried = ladder.beginResolveRetry()
        #expect(retried)
        // The retry resolves and gets a new candidate set…
        ladder.replaceCandidates(candidates(2))
        #expect(ladder.next()?.adapterIndex == 1)
        #expect(ladder.next() == nil)

        // …and is still not allowed to retry again.
        let retriedAgain = ladder.beginResolveRetry()
        #expect(!retriedAgain)
        #expect(!ladder.canRetryResolve)
    }

    @Test("reset clears the ladder and the retry allowance")
    func resetClearsEverything() {
        var ladder = FallbackLadder(candidates: candidates(2))
        _ = ladder.beginResolveRetry()
        ladder.reset()

        #expect(ladder.startedFrom == nil)
        #expect(ladder.remainingCount == 0)
        #expect(ladder.canRetryResolve)
    }

    /// The view model uses `startedFrom != nil` as "this request has a resolved candidate set", so
    /// it can ignore a failure that belongs to the item being replaced. A successful resolve always
    /// installs at least one candidate, and `reset` clears it — pinned here so the guard cannot go
    /// stale.
    @Test("a ladder reports unresolved until a candidate set is installed, and reset clears it")
    func resolvedStateIsObservable() {
        var ladder = FallbackLadder()
        #expect(ladder.startedFrom == nil)

        ladder.replaceCandidates(candidates(2))
        #expect(ladder.startedFrom != nil)

        // Consuming every fallback does not clear it — only a new request does.
        _ = ladder.next()
        _ = ladder.next()
        #expect(ladder.startedFrom != nil)

        ladder.reset()
        #expect(ladder.startedFrom == nil)
    }

    @Test("an empty ladder terminates immediately")
    func emptyLadder() {
        var ladder = FallbackLadder(candidates: [])
        #expect(ladder.startedFrom == nil)
        #expect(ladder.next() == nil)
        let first = ladder.beginResolveRetry()
        let second = ladder.beginResolveRetry()
        #expect(first)
        #expect(!second)
    }
}

// MARK: - Active stream diagnostics

@Suite("Active stream diagnostics")
struct ActiveStreamDiagnosticTests {
    private func activeCandidate(
        mime: String? = "audio/mp4",
        bitrate: Int? = 128_000,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        path: String = "signed"
    ) -> PlaybackCandidate {
        makeCandidate(
            makeStream(path: path, mime: mime, bitrate: bitrate, bitDepth: bitDepth, sampleRate: sampleRate),
            source: "youtube_music"
        )
    }

    @Test("the summary describes the candidate that is playing")
    func summaryUsesActiveCandidate() {
        let info = ActiveStreamInfo(
            candidate: activeCandidate(mime: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 128_000),
            sourceDisplayName: "YouTube Music",
            isFallback: false
        )
        #expect(info.container == "audio/mp4")
        #expect(info.codec == "mp4a.40.2")
        #expect(ActiveStreamDiagnostic.summary(.active(info)) == "YouTube Music · audio/mp4 · mp4a.40.2 · 128 kbps")
    }

    @Test("a fallback is labelled and describes the fallback's own stream")
    func fallbackDescribesItself() {
        let hls = makeCandidate(makeStream(path: "h", kind: .hls, mime: "application/x-mpegURL"), source: "youtube_music")
        let info = ActiveStreamInfo(candidate: hls, sourceDisplayName: "YouTube Music", isFallback: true)

        let summary = ActiveStreamDiagnostic.summary(.active(info))
        #expect(summary?.hasPrefix("Fallback · ") == true)
        #expect(summary?.contains("application/x-mpegURL") == true)

        let rows = ActiveStreamDiagnostic.rows(.active(info))
        #expect(rows.contains(.init(label: "Fallback", value: "Yes")))
        #expect(rows.contains(.init(label: "Stream", value: "adaptive manifest (HLS)")))
    }

    @Test("unknown properties are omitted from the summary and explicit in the rows")
    func unknownIsHonest() {
        let info = ActiveStreamInfo(candidate: activeCandidate(mime: "audio/mp4", bitrate: nil), sourceDisplayName: nil, isFallback: false)
        #expect(ActiveStreamDiagnostic.summary(.active(info)) == "youtube_music · audio/mp4")

        let rows = ActiveStreamDiagnostic.rows(.active(info))
        #expect(rows.contains(.init(label: "Bitrate", value: "Unknown")))
        #expect(rows.contains(.init(label: "Sample Rate", value: "Unknown")))
        #expect(rows.contains(.init(label: "Codec", value: "Unknown")))
        #expect(rows.contains(.init(label: "Quality Evidence", value: "unknown")))
    }

    @Test("a stream with nothing known still produces a truthful summary")
    func nothingKnown() {
        let bare = makeCandidate(makeStream(path: "b", mime: nil), source: "youtube_music")
        let info = ActiveStreamInfo(candidate: bare, sourceDisplayName: nil, isFallback: false)
        #expect(ActiveStreamDiagnostic.summary(.active(info)) == "youtube_music")
        #expect(info.evidence == .unknown)
    }

    @Test("resolving, failed and idle are distinguishable and never invent a stream")
    func nonActiveStates() {
        #expect(ActiveStreamDiagnostic.summary(.idle) == nil)
        #expect(ActiveStreamDiagnostic.summary(.resolving) == "Resolving stream…")
        #expect(ActiveStreamDiagnostic.summary(.failed) == "Stream unavailable")
        #expect(ActiveStreamDiagnostic.rows(.resolving).count == 1)
        #expect(ActiveStreamDiagnostic.rows(.idle) == [.init(label: "Status", value: "Idle")])
    }

    /// Sensitive transport data cannot reach the UI because it is structurally absent from
    /// `ActiveStreamInfo` — asserted on the output, since that is what a view would render.
    @Test("no URL, header or token can appear in any diagnostic output")
    func noSensitiveData() throws {
        let signed = try SourceStream(
            url: #require(URL(string: "https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&sig=SECRET&pot=TOKEN")),
            kind: .direct,
            mimeType: "audio/mp4",
            bitrate: 128_000,
            headers: ["Authorization": "Bearer super-secret", "Cookie": "session=abc"]
        )
        let candidate = makeCandidate(signed, source: "youtube_music")
        let info = ActiveStreamInfo(candidate: candidate, sourceDisplayName: "YouTube Music", isFallback: false)

        let rendered = [
            ActiveStreamDiagnostic.summary(.active(info)) ?? "",
            ActiveStreamDiagnostic.rows(.active(info)).map { "\($0.label) \($0.value)" }.joined(separator: " "),
            String(describing: info),
        ].joined(separator: "\n")

        for forbidden in ["googlevideo", "http", "Authorization", "Bearer", "secret", "Cookie", "sig=", "pot=", "session="] {
            #expect(!rendered.localizedCaseInsensitiveContains(forbidden), "leaked: \(forbidden)")
        }
    }
}

// MARK: - Active stream tracking (staleness)

@Suite("Active stream tracker")
struct ActiveStreamTrackerTests {
    private func candidate(_ index: Int = 0, mime: String = "audio/mp4") -> PlaybackCandidate {
        makeCandidate(makeStream(path: "s\(index)", mime: mime), index: index)
    }

    @Test("a request starts as resolving, and activating records the stream")
    func activate() {
        var tracker = ActiveStreamTracker()
        #expect(tracker.state == .idle)

        tracker.begin(requestID: 1)
        #expect(tracker.state == .resolving)

        let activated = tracker.activate(requestID: 1, candidate: candidate(), sourceDisplayName: "YouTube Music", isFallback: false)
        #expect(activated)
        guard case let .active(info) = tracker.state else {
            Issue.record("expected an active state")
            return
        }
        #expect(info.sourceDisplayName == "YouTube Music")
        #expect(!info.isFallback)
    }

    /// The staleness guard: a resolve for the track the user just left cannot describe it.
    @Test("an update for a superseded request is ignored")
    func staleUpdateIgnored() {
        var tracker = ActiveStreamTracker()
        tracker.begin(requestID: 1)
        tracker.activate(requestID: 1, candidate: candidate(0), sourceDisplayName: nil, isFallback: false)

        tracker.begin(requestID: 2)
        #expect(tracker.state == .resolving)

        // The previous request's late result must not land.
        let staleActivate = tracker.activate(requestID: 1, candidate: candidate(1), sourceDisplayName: nil, isFallback: false)
        #expect(!staleActivate)
        #expect(tracker.state == .resolving)
        let staleFail = tracker.fail(requestID: 1)
        #expect(!staleFail)
        #expect(tracker.state == .resolving)

        // The current one does.
        let currentActivate = tracker.activate(requestID: 2, candidate: candidate(2), sourceDisplayName: nil, isFallback: false)
        #expect(currentActivate)
    }

    @Test("failure is recorded for the current request only")
    func failRecordsOnlyForCurrent() {
        var tracker = ActiveStreamTracker()
        tracker.begin(requestID: 5)
        let staleFail = tracker.fail(requestID: 4)
        let currentFail = tracker.fail(requestID: 5)
        #expect(!staleFail)
        #expect(currentFail)
        #expect(tracker.state == .failed)
    }

    @Test("stopping clears the stream and invalidates an in-flight request")
    func stopClears() {
        var tracker = ActiveStreamTracker()
        tracker.begin(requestID: 1)
        tracker.activate(requestID: 1, candidate: candidate(), sourceDisplayName: nil, isFallback: false)

        tracker.stop()
        #expect(tracker.state == .idle)
        #expect(ActiveStreamDiagnostic.summary(tracker.state) == nil)

        // The request that was in flight can no longer publish anything.
        let late = tracker.activate(requestID: 1, candidate: candidate(), sourceDisplayName: nil, isFallback: false)
        #expect(!late)
        #expect(tracker.state == .idle)
    }
}
