//
//  PlaybackResolver.swift
//  Player
//
//  The three-step lookup. This is where "don't search again" actually happens.
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
/// 1. SongSource has a fresh cached URL   → play it.        ZERO network calls.
/// 2. Cached URL stale, track id known    → resolve by id.  NO search.
/// 3. No representation on this source    → match once, persist, then step 2.
/// ```
///
/// Step 3 runs **once per (song, source) pair, ever**. The previous implementation ran the
/// equivalent of step 3 on every single play, because a queue entry carried a resolver closure
/// rather than an identity and so had nothing to cache against.
@MainActor
public final class PlaybackResolver {
    private let sources: SourceRegistry
    private let matcher: SongMatcher
    private let selector: StreamSelector

    /// Looks up the persisted binding and cached URL for a ref.
    ///
    /// A closure rather than a store reference so Player stays free of SwiftData — persistence is
    /// the application's concern, and the resolver only needs two questions answered.
    public var lookup: (@MainActor (PlayableRef) -> SongSource?)?

    /// Persists a newly-discovered binding, so step 3 never runs again for this pair.
    public var persist: (@MainActor (PlayableRef, SourceTrack, SourceStream) -> Void)?

    public init(
        sources: SourceRegistry,
        matcher: SongMatcher = SongMatcher(),
        selector: StreamSelector = StreamSelector()
    ) {
        self.sources = sources
        self.matcher = matcher
        self.selector = selector
    }

    /// Resolves a playable stream.
    public func resolve(_ ref: PlayableRef) async throws -> SourceStream {
        let span = CisumSignpost.resolver.begin("stream-resolve", "\(ref.sourceID) \(ref.title)")
        defer { CisumSignpost.resolver.end("stream-resolve", state: span) }

        // ── Step 1: a cached URL that is still good. No network at all. ──────────────────
        if let binding = lookup?(ref), let cached = binding.freshStreamURL() {
            CisumSignpost.cache.event("cache-hit", "\(ref.sourceID) \(ref.title)")
            return SourceStream(
                url: cached,
                kind: cached.pathExtension.lowercased() == "m3u8" ? .hls : .direct,
                mimeType: binding.cachedStreamMIMEType,
                expiresAt: binding.cachedStreamExpiresAt,
                isCacheable: binding.allowsStreamCaching
            )
        }
        CisumSignpost.cache.event("cache-miss", "\(ref.sourceID) \(ref.title)")

        guard let source = sources.source(for: ref.sourceID) else {
            throw ResolutionError.sourceUnavailable(ref.sourceID)
        }

        // ── Step 2: the track id is known. Resolve directly, no search. ─────────────────
        do {
            let stream = try await source.stream(trackID: ref.sourceTrackID, quality: selector.preferred)
            persistIfPossible(ref, stream: stream)
            return stream
        } catch {
            // A stored id can stop working: two known modules mint a session token at load time
            // and embed it in every track id, so yesterday's id is meaningless today. Falling back
            // to a fresh match is the correct response, not surfacing an error.
            PerfLog.warning("Direct resolve failed for \(ref.sourceID)/\(ref.sourceTrackID): \(error.localizedDescription). Re-matching.")
        }

        // ── Step 3: re-match, then persist so this never happens again for this pair. ───
        let target = MatchTarget(
            title: ref.title,
            artist: ref.artist,
            durationSeconds: ref.durationSeconds
        )

        guard let match = try await matcher.match(target, on: source) else {
            throw ResolutionError.noMatch(source: ref.sourceID, title: ref.title)
        }

        let stream = try await source.stream(trackID: match.track.id, quality: selector.preferred)
        persist?(ref, match.track, stream)
        return stream
    }

    private func persistIfPossible(_ ref: PlayableRef, stream: SourceStream) {
        // The binding is already correct; only the cached URL needs refreshing. Reusing `persist`
        // with a synthesised track keeps one write path rather than two.
        let track = SourceTrack(
            id: ref.sourceTrackID,
            title: ref.title,
            artist: ref.artist,
            durationSeconds: ref.durationSeconds
        )
        persist?(ref, track, stream)
    }
}

public enum ResolutionError: Error, LocalizedError, Equatable {
    case sourceUnavailable(String)
    case noMatch(source: String, title: String)

    public var errorDescription: String? {
        switch self {
        case let .sourceUnavailable(id):
            "The source \(id) is not available. It may be disabled or failed to load."
        case let .noMatch(source, title):
            "Could not find \"\(title)\" on \(source)."
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
        self.sources = sources
        if let preferredSourceID, !sources.contains(where: { $0.id == preferredSourceID }) {
            self.preferredSourceID = sources.first?.id
        }
    }

    public func source(for id: String) -> (any MusicSource)? {
        sources.first { $0.id == id }
    }

    /// Sources that can actually play audio, in preference order.
    public var playable: [any MusicSource] {
        let capable = sources.filter { $0.capabilities.contains(.stream) }
        guard let preferredSourceID,
              let index = capable.firstIndex(where: { $0.id == preferredSourceID })
        else { return capable }

        var ordered = capable
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}
