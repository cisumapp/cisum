//
//  PlaybackResolver.swift
//  Player
//
//  The three-step lookup, now with every provider that knows the track.
//

import Foundation
import Models
import ProviderSDK
import Utilities

/// Turns a `PlayableRef` into a playable URL, as cheaply as possible.
///
/// The whole point of the architecture reset lives in `resolve(_:)`:
///
/// ```
/// 1. SongSource has a fresh cached URL        → play it.                    ZERO network calls.
/// 2. Any provider already knows the track id  → resolve by id, in parallel. NO search.
/// 3. No provider knows it                     → search, in parallel, once.  Then persist.
/// ```
///
/// Step 3 runs **once per (song, source) pair, ever**. The previous implementation ran the
/// equivalent of step 3 on every single play, because a queue entry carried a resolver closure
/// rather than an identity and so had nothing to cache against.
///
/// **Candidate selection happens here, across providers.** Two decisions make that real:
///
/// - Every provider that already knows the track contributes candidates, not just the ref's own
///   source. A stream on another service is only playable if cisum knows *which* track on that
///   service it is, and a persisted representation is exactly that statement — so this costs one
///   HTTP call per provider and no search at all.
/// - They are resolved **concurrently** (`CandidateCollection`) and ranked together
///   (`CandidateRankingPolicy`). The previous implementation walked the provider list and returned
///   on the first provider that produced anything usable, which meant the provider order in the
///   registry decided what played: a better stream further down the list could never win.
///
/// The providers' own orders survive only as the final tie-breaks. Collecting stops once the
/// ranking has had a chance to consider more than the answer it already holds: an
/// `improvementWindow` after the first usable candidate, and never before one exists — see
/// `ResolutionBudget` for why those are two different windows.
@MainActor
public final class PlaybackResolver {
    private let sources: SourceRegistry
    private let matcher: SongMatcher
    private let selector: StreamSelector

    /// The ranking policy applied to every candidate set. Holds the quality configuration
    /// (`StreamSelector`) the caller used to hand in.
    public var ranking: CandidateRankingPolicy

    /// Every persisted representation cisum has of this track — the ref's own source first, then the
    /// other providers that already know it.
    ///
    /// A closure rather than a store reference so Player stays free of SwiftData — persistence is
    /// the application's concern, and the resolver only needs one question answered. Returning *all*
    /// representations rather than one is what lets another provider compete for the same recording.
    public var bindings: (@MainActor (PlayableRef) -> [SongSource])?

    /// Persists a newly-discovered binding, so step 3 never runs again for this pair.
    public var persist: (@MainActor (PlayableRef, SourceTrack, SourceStream) -> Void)?

    /// Reports how a stream was obtained, for the playback-resolution metrics.
    ///
    /// Instrumentation only — called on the success paths and changing no resolution behaviour.
    /// Carries the documented warm/cold classification (`PlaybackResolutionPath`) and the elapsed
    /// milliseconds. Failures and empty results are deliberately not reported here; they surface as
    /// a thrown error and are counted by the caller.
    public var onResolveOutcome: (@MainActor (PlaybackResolutionPath, Double) -> Void)?

    /// How much cisum trusts a source, for the ranking policy's trust dimension.
    ///
    /// **Injected, not self-declared.** A provider cannot promote itself by claiming anything, and a
    /// plugin cisum has never seen cannot answer this by existing. When the composition root does
    /// not supply it, the answer is `.unknown` and ranking falls through to its other tiers.
    public var sourceTrust: (@MainActor (String) -> SourceTrust)?

    /// How long the request is willing to wait for candidates. See `ResolutionBudget`.
    ///
    /// Note what this is *not*: it is not a per-provider latency budget. A provider slower than
    /// `improvementWindow` still plays when it is the only one that can — the window only limits how
    /// long an already-available candidate is held back while other providers are asked.
    public var budget: ResolutionBudget

    public init(
        sources: SourceRegistry,
        matcher: SongMatcher = SongMatcher(),
        selector: StreamSelector = StreamSelector(),
        ranking: CandidateRankingPolicy? = nil,
        budget: ResolutionBudget = .default
    ) {
        self.sources = sources
        self.matcher = matcher
        self.selector = selector
        self.ranking = ranking ?? CandidateRankingPolicy(quality: selector)
        self.budget = budget
    }

    /// Resolves a playable stream.
    ///
    /// - Returns: Every usable candidate, **ranked best first**. Never empty on success.
    public func resolve(_ ref: PlayableRef) async throws -> [PlaybackCandidate] {
        let span = CisumSignpost.resolver.begin("stream-resolve", "\(ref.sourceID) \(ref.title)")
        defer { CisumSignpost.resolver.end("stream-resolve", state: span) }

        PerfLog.info("PlaybackResolver.resolve(): starting for sourceID='\(ref.sourceID)' trackID='\(ref.sourceTrackID)' title='\(ref.title)'")
        let resolveStart = ContinuousClock.now

        // Local, not resolver state: two requests can be in flight at once and each must classify
        // its own failure rather than whatever the other one happened to record.
        var stageReports: [SourceResolveReport] = []

        // One read for the whole resolve: step 1 needs a cached URL, step 2 needs to know every
        // provider that already has a representation of this recording.
        let known = bindings?(ref) ?? []
        PerfLog.trace("PlaybackResolver: \(known.count) persisted representation(s): \(known.map(\.sourceID))")

        // ── Step 1: a cached URL that is still good. No network at all. ──────────────────
        if let binding = freshestCachedStream(among: known, preferring: ref.sourceID),
           let cached = binding.freshStreamURL()
        {
            CisumSignpost.cache.event("cache-hit", "\(binding.sourceID) \(ref.title)")
            // The host only. A signed CDN URL is a credential: it is usable by anyone who reads it
            // until it expires, so it does not belong in a log line.
            PerfLog.info("PlaybackResolver: Step 1 CACHED URL — \(binding.sourceID) host=\(cached.host ?? "unknown")")
            let cachedStream = SourceStream(
                url: cached,
                kind: cached.pathExtension.lowercased() == "m3u8" ? .hls : .direct,
                mimeType: binding.cachedStreamMIMEType,
                expiresAt: binding.cachedStreamExpiresAt,
                isCacheable: binding.allowsStreamCaching,
                headers: binding.cachedStreamHeaders,
                // The binding's length is the persisted stream's own (see `persist`).
                durationSeconds: binding.durationSeconds
            )
            // A binding exists by construction here, so the recording is established. There is
            // nothing to rank against — one candidate.
            let candidate = PlaybackCandidate(
                stream: cachedStream,
                sourceID: binding.sourceID,
                sourceTrackID: binding.sourceTrackID,
                identity: .confirmed(.establishedBinding),
                trust: trust(for: binding.sourceID),
                qualityEvidence: .advertised
            )
            reportResolveOutcome(.cachedStreamURL, since: resolveStart)
            return ranking.rank([candidate]).ranked
        }
        CisumSignpost.cache.event("cache-miss", "\(ref.sourceID) \(ref.title)")
        PerfLog.trace("PlaybackResolver: Step 1 cache miss — no fresh cached URL for \(ref.sourceID)/\(ref.sourceTrackID)")

        // ── Step 2: resolve by stored id, on every provider that already knows this track. ──────
        //
        // No search is involved: every job here has an id cisum already stored. The ref's own source
        // is a job only when it advertises `.stream` — some services are metadata-only from cisum's
        // point of view (Spotify has the best catalogue data but its API returns no playable audio),
        // so a Spotify ref means "this track, identified by Spotify", not "play it from Spotify".
        let directJobs = directJobs(ref: ref, known: known)
        if !directJobs.isEmpty {
            let reports = await CandidateCollection.collect(directJobs, within: budget)
            stageReports = reports
            let ranked = rank(reports)
            log(ranked, reports: reports, stage: "by stored id")
            if let selected = ranked.selected {
                reportResolveOutcome(.directProviderID, since: resolveStart)
                // Stale-write guard: a superseded request must not overwrite newer binding state.
                // `loadTask?.cancel()` runs the moment the user selects another track, so a cancelled
                // resolve persists nothing. The **selected** stream is what is persisted, since that
                // is what will actually play.
                if !Task.isCancelled {
                    persist(selected, ref: ref)
                }
                return ranked.ranked
            }
            PerfLog.warning("PlaybackResolver: Step 2 — no provider produced a usable candidate for '\(ref.title)'; searching")
        }

        // ── Step 3: search every playable provider, once, and persist the winner. ───────────────
        //
        // This replaces what the search layer used to call the "hidden fallback" — resolving a
        // Spotify result by searching YouTube for it. Same behaviour, correct location: it needs the
        // matcher and the source registry, neither of which belongs in a search view model, and doing
        // it here means the binding gets persisted so it happens once rather than on every play.
        //
        // Concurrent, so which provider wins is a ranking decision rather than a list position, and
        // so the wait is the slowest provider instead of the sum of all of them.
        let target = MatchTarget(
            title: ref.title,
            artist: ref.artist,
            album: ref.album,
            durationSeconds: ref.durationSeconds,
            isrc: ref.isrc
        )
        let searchJobs = searchJobs(for: target)
        PerfLog.info("PlaybackResolver: Step 3 — searching \(searchJobs.count) playable source(s): \(searchJobs.map(\.sourceID))")

        if !searchJobs.isEmpty {
            let reports = await CandidateCollection.collect(searchJobs, within: budget)
            stageReports = reports
            let ranked = rank(reports)
            log(ranked, reports: reports, stage: "searched")
            if let selected = ranked.selected {
                PerfLog.info("PlaybackResolver: Step 3 — resolved '\(ref.title)' from '\(selected.sourceID)' (host=\(selected.stream.url.host ?? "unknown"))")
                reportResolveOutcome(.matchedProvider, since: resolveStart)
                if !Task.isCancelled {
                    persist(selected, ref: ref)
                }
                return ranked.ranked
            }
        }

        PerfLog.error("PlaybackResolver: FAILED to resolve '\(ref.title)' from source '\(ref.sourceID)' — no provider produced a playable candidate")
        throw ResolutionError.noMatch(
            source: ref.sourceID,
            title: ref.title,
            underlying: firstFailure(in: stageReports)
        )
    }

    // MARK: - Candidate sources

    /// The still-fresh cached URL to replay, if there is one.
    ///
    /// Preferred order: the **most recently resolved** representation first, then the ref's own
    /// source, then source id for determinism.
    ///
    /// Recency leads deliberately. cisum does not persist stream quality (`SongSource` keeps the URL,
    /// MIME type, headers and expiry — not bitrate), so when several representations are cached there
    /// is no evidence in which to compare them, and the last stream the *ranker chose* is the closest
    /// thing to one. Ties fall to the source the user asked for. This is the mechanism that stops a
    /// cross-provider selection from being undone by the warm path replaying a different provider's
    /// older cached URL.
    private func freshestCachedStream(among bindings: [SongSource], preferring sourceID: String) -> SongSource? {
        func resolvedAt(_ binding: SongSource) -> Date {
            binding.cachedStreamResolvedAt ?? .distantPast
        }
        return bindings
            .filter { $0.freshStreamURL() != nil }
            .min { lhs, rhs in
                if resolvedAt(lhs) != resolvedAt(rhs) {
                    return resolvedAt(lhs) > resolvedAt(rhs)
                }
                if (lhs.sourceID == sourceID) != (rhs.sourceID == sourceID) {
                    return lhs.sourceID == sourceID
                }
                return lhs.sourceID < rhs.sourceID
            }
    }

    /// Jobs that need no search: one per provider that already has an id for this track.
    ///
    /// The ref's own source comes first because it is the provider the user asked for, which is both
    /// the cheapest candidate to obtain and the tie-break if two providers offer the same quality.
    private func directJobs(ref: PlayableRef, known: [SongSource]) -> [SourceResolveJob] {
        var plans: [(source: any MusicSource, trackID: String, identity: CandidateIdentity)] = []
        var planned = Set<String>()

        if let source = sources.source(for: ref.sourceID), source.capabilities.contains(.stream) {
            plans.append((
                source,
                ref.sourceTrackID,
                identity(for: ref, hasBinding: known.contains { $0.sourceID == ref.sourceID })
            ))
            planned.insert(ref.sourceID)
        }

        for binding in known where !planned.contains(binding.sourceID) {
            guard let source = sources.source(for: binding.sourceID), source.capabilities.contains(.stream) else {
                // A representation on a service cisum cannot stream from — Spotify, typically. Not an
                // error: the representation is still identity evidence, it just is not a transport.
                PerfLog.trace("PlaybackResolver: representation on '\(binding.sourceID)' is not stream-capable; skipping")
                continue
            }
            planned.insert(binding.sourceID)
            plans.append((source, binding.sourceTrackID, .confirmed(.establishedBinding)))
        }

        let quality = selector.preferred
        return plans.enumerated().map { order, plan in
            SourceResolveJob(sourceID: plan.source.id, order: order) {
                let streams = try await plan.source.streamCandidates(
                    trackID: plan.trackID,
                    quality: quality
                )
                return SourceStreams(trackID: plan.trackID, streams: streams, identity: plan.identity)
            }
        }
    }

    /// Jobs that search, for providers with no stored id. Only reached when nothing cisum already
    /// knows can play the track.
    private func searchJobs(for target: MatchTarget) -> [SourceResolveJob] {
        // Captured by value: the job closures are `@Sendable`, and neither the matcher nor the
        // source needs anything from the resolver once the job starts.
        let songMatcher = matcher
        let quality = selector.preferred
        return sources.playable.enumerated().map { order, source in
            SourceResolveJob(sourceID: source.id, order: order) {
                // `SongMatcher` accepts a match only when `VariantDetector` agrees the versions are
                // compatible and the score clears its gate, so an incompatible recording never
                // becomes a candidate here. An unacceptable match is `.nothing`, not a failure.
                guard let match = try await songMatcher.match(target, on: source) else { return nil }
                let streams = try await source.streamCandidates(trackID: match.track.id, quality: quality)
                // How the match was established is the identity evidence the ranker gates on.
                return SourceStreams(
                    trackID: match.track.id,
                    streams: streams,
                    identity: Self.searchIdentity(for: match)
                )
            }
        }
    }

    /// The identity evidence a search match carries into ranking.
    ///
    /// A music video that cleared the matcher is the right *song* but often not the right *edit* —
    /// intro skits, outros, a radio cut. It stays playable as a last resort, but as `.unconfirmed`,
    /// so the official audio from any other provider outranks it before quality is compared.
    nonisolated static func searchIdentity(for match: MatchResult) -> CandidateIdentity {
        if match.isExact {
            return .confirmed(.exactISRC)
        }
        if match.track.recordingKind == .musicVideo {
            return .unconfirmed
        }
        return .confirmed(.confidentMatch)
    }

    /// The identity evidence available for a direct resolve on the ref's own source.
    ///
    /// A persisted binding is the strongest evidence cisum has; a canonical `songID` without a
    /// binding means the mapping was established elsewhere; an ad-hoc play of a search result has
    /// nothing but the user's tap. None of them is a *disagreement*, so none is rejected — identity
    /// is only allowed to reorder here, never to disqualify.
    private func identity(for ref: PlayableRef, hasBinding: Bool) -> CandidateIdentity {
        if hasBinding {
            return .confirmed(.establishedBinding)
        }
        if ref.songID != nil {
            return .confirmed(.confidentMatch)
        }
        return .unconfirmed
    }

    private func trust(for sourceID: String) -> SourceTrust {
        sourceTrust?(sourceID) ?? .unknown
    }

    // MARK: - Candidate building and ranking

    /// Builds one candidate set from every provider's contribution and ranks it.
    ///
    /// The adapter's array order becomes `adapterIndex` and the provider's position in the
    /// preference order becomes `sourceOrder`; both are only tie-breaks, so neither a shuffled
    /// adapter list nor registry order can change which stream wins on merit.
    private func rank(_ reports: [SourceResolveReport]) -> CandidateRanking {
        let candidates = reports.flatMap { report -> [PlaybackCandidate] in
            guard let contribution = report.streams else { return [] }
            let trust = trust(for: report.sourceID)
            return contribution.streams.enumerated().map { index, stream in
                PlaybackCandidate(
                    stream: stream,
                    sourceID: report.sourceID,
                    sourceTrackID: contribution.trackID,
                    identity: contribution.identity,
                    trust: trust,
                    // Everything a provider reports about quality is *advertised*: no adapter measures
                    // the delivered stream, and `PlaybackCandidate.evidence` reports `.unknown` when
                    // the numbers are absent.
                    qualityEvidence: .advertised,
                    adapterIndex: index,
                    sourceOrder: report.order
                )
            }
        }

        return ranking.rank(candidates)
    }

    /// Records what each provider did, and the selection, so a wrong choice is diagnosable from a log
    /// rather than only from the audio.
    ///
    /// One line per stage plus one per rejected candidate — bounded regardless of how many streams a
    /// provider returned, and free of URLs, headers and tokens.
    private func log(_ result: CandidateRanking, reports: [SourceResolveReport], stage: String) {
        let summary = reports.map { report -> String in
            switch report.result {
            case let .answered(streams): "\(report.sourceID): \(streams.streams.count) stream(s)"
            case .nothing: "\(report.sourceID): no representation"
            case .timedOut: "\(report.sourceID): timed out"
            case let .failed(reason): "\(report.sourceID): failed (\(reason))"
            }
        }
        PerfLog.info("Candidate ranking [\(stage)]: \(summary.joined(separator: ", ")) → \(result.ranked.count) usable, \(result.rejected.count) rejected")

        for rejected in result.rejected {
            PerfLog.warning("Candidate ranking rejected \(rejected.candidate.sourceID) candidate #\(rejected.candidate.adapterIndex) (\(rejected.candidate.stream.mimeType ?? "container not reported")): \(rejected.reason.description)")
        }

        guard let selected = result.selected else { return }
        PerfLog.info(
            "Candidate ranking selected #\(selected.adapterIndex) on \(selected.sourceID)"
                + " — \(selected.transportClass), evidence=\(selected.evidence),"
                + " trust=\(selected.trust), of \(result.ranked.count) usable"
        )
        // "The only candidate" and "the candidate that matched" are different facts, and the ranking
        // cannot tell the user which one this is — it can only say what it knows. Selecting an
        // unconfirmed candidate because nothing else exists is the right call (a missing match must
        // not become a dead end), but it is also the shape a wrong-recording report takes, so it is
        // recorded as what it is rather than left to look like a confident match.
        if result.ranked.count == 1, selected.identity == .unconfirmed {
            PerfLog.warning(
                "Candidate ranking selected \(selected.sourceID) as the ONLY candidate, with no"
                    + " identity evidence beyond the request itself — no alternative was available to"
                    + " prefer over it"
            )
        }
        CisumSignpost.resolver.event("candidate-selected", "\(selected.sourceID) #\(selected.adapterIndex)")
    }

    /// Persists the stream that will actually play, against **its own** provider binding.
    ///
    /// Not against the ref's source: with candidates from several providers the winner can come from
    /// another one, and writing its URL into the ref's binding would make the warm path replay a
    /// stream from a provider that was not chosen.
    private func persist(_ candidate: PlaybackCandidate, ref: PlayableRef) {
        let track = SourceTrack(
            id: candidate.sourceTrackID,
            title: ref.title,
            artist: ref.artist,
            // The file's own length when the service states it, so a cached replay keeps it.
            durationSeconds: candidate.stream.durationSeconds ?? ref.durationSeconds
        )
        let playbackRef = PlayableRef(
            songID: ref.songID,
            sourceID: candidate.sourceID,
            sourceTrackID: candidate.sourceTrackID,
            title: ref.title,
            artist: ref.artist,
            artworkURL: ref.artworkURL,
            durationSeconds: ref.durationSeconds,
            isrc: ref.isrc,
            album: ref.album
        )
        persist?(playbackRef, track, candidate.stream)
    }

    private func reportResolveOutcome(_ path: PlaybackResolutionPath, since start: ContinuousClock.Instant) {
        guard let onResolveOutcome else { return }
        onResolveOutcome(path, start.duration(to: ContinuousClock.now).milliseconds)
    }

    /// The first provider failure, for the thrown error.
    ///
    /// Deliberately carries the error's **type name rather than its message**: a provider error
    /// message is free-form text that can embed the URL it failed on, and this value ends up in a
    /// user-visible `errorDescription` and in the log.
    private func firstFailure(in reports: [SourceResolveReport]) -> (any Error)? {
        for report in reports {
            if case let .failed(reason) = report.result {
                return ProviderFailure(sourceID: report.sourceID, reason: reason)
            }
        }
        return nil
    }
}

/// A provider that threw while resolving.
struct ProviderFailure: Error, LocalizedError {
    let sourceID: String
    /// The error's type name. Never its message — see `firstFailure(in:)`.
    let reason: String

    var errorDescription: String? {
        "\(sourceID) failed to resolve the stream (\(reason))"
    }
}

/// Not Equatable: it carries the underlying error, which is what made this failure
/// diagnosable at all. Nothing compares these.
public enum ResolutionError: Error, LocalizedError {
    case sourceUnavailable(String)
    case noMatch(source: String, title: String, underlying: (any Error)?)

    public var errorDescription: String? {
        switch self {
        case let .sourceUnavailable(id):
            "The source \(id) is not available. It may be disabled or failed to load."
        case let .noMatch(source, title, underlying):
            "Could not find \"\(title)\" on \(source)."
                + (underlying.map { " (\($0))" } ?? "")
        }
    }
}

/// The sources available to play from.
///
/// Player holds `any MusicSource` values and never learns whether one came from a JavaScript
/// plugin, a JSON manifest, or a native Swift SDK. The composition root builds this.
@MainActor
@Observable
public final class SourceRegistry {
    public private(set) var sources: [any MusicSource] = []

    /// The source used when nothing more specific is requested.
    public var preferredSourceID: String?

    public init(sources: [any MusicSource] = []) {
        self.sources = sources
    }

    public func replace(with sources: [any MusicSource]) {
        PerfLog.info("SourceRegistry.replace(with:): replacing \(self.sources.count) sources with \(sources.count) sources: \(sources.map { "\($0.id) caps=\($0.capabilities)" })")
        self.sources = sources
        if let preferredSourceID, !sources.contains(where: { $0.id == preferredSourceID }) {
            let newPreferred = sources.first?.id
            PerfLog.warning("SourceRegistry: preferredSourceID '\(preferredSourceID)' not found in new sources — falling back to '\(newPreferred ?? "nil")'")
            self.preferredSourceID = newPreferred
        } else {
            PerfLog.info("SourceRegistry: preferredSourceID=\(preferredSourceID ?? "nil")")
        }
    }

    public func source(for id: String) -> (any MusicSource)? {
        let source = sources.first { $0.id == id }
        if source == nil {
            PerfLog.warning("SourceRegistry.source(for: '\(id)'): NOT FOUND. Available sources: \(sources.map(\.id))")
        } else {
            PerfLog.trace("SourceRegistry.source(for: '\(id)'): found \(source!.id) caps=\(source!.capabilities)")
        }
        return source
    }

    /// A source's display name, without the "not found" warning `source(for:)` logs.
    ///
    /// Diagnostics need to name the source that actually served a stream, and a lookup that misses
    /// there is not an error worth logging.
    public func displayName(for id: String) -> String? {
        sources.first { $0.id == id }?.displayName
    }

    /// Sources that can actually play audio, in preference order.
    public var playable: [any MusicSource] {
        let capable = sources.filter { $0.capabilities.contains(.stream) }
        PerfLog.trace("SourceRegistry.playable: \(capable.count) of \(sources.count) sources have .stream capability: \(capable.map(\.id))")
        guard let preferredSourceID,
              let index = capable.firstIndex(where: { $0.id == preferredSourceID })
        else { return capable }

        var ordered = capable
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}
