//
//  SongMatcher.swift
//  Player
//
//  Binding a canonical song to one service's track. Once, ever, per pair.
//

import Foundation
import Models
import ProviderSDK
import Utilities

/// What cisum is looking for.
public struct MatchTarget: Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSeconds: Double?
    public let isrc: String?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double? = nil,
        isrc: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }

    public init(song: Song) {
        self.init(
            title: song.title,
            artist: song.primaryArtistName ?? "",
            album: song.albumTitle,
            durationSeconds: song.durationSeconds,
            isrc: song.isrc
        )
    }
}

/// A candidate and why it scored what it did.
public struct MatchResult: Sendable {
    public let track: SourceTrack
    public let score: Double
    public let variant: RecordingVariant
    /// Set when the match is certain because the ISRCs agree.
    public let isExact: Bool
}

/// Finds which track on a given service corresponds to a song cisum already knows about.
///
/// **This is the only "are these the same track?" implementation in cisum.** The previous
/// architecture had six, spread across two packages, which disagreed with each other:
/// `ReconciliationEngine.scoreMatch`, `CrossProviderDeduplicator.isSameRecording`,
/// `ExplicitFilter.pairsForExplicitFilter`, `YouTubeStreamResolver.pickBestSearchResult`,
/// `ProviderSDKStreamResolver.scoreTrack` (twice), and `PlayerViewModel+Queue.bestRadioSeedSong`.
///
/// It runs **once per (song, source) pair, ever**. The binding is persisted to `SongSource`, so
/// the second play of a track is a lookup rather than a search.
public struct SongMatcher: Sendable {
    /// Below this, no candidate is accepted and the search is treated as failed.
    ///
    /// Refusing to match is a real outcome. The old resolver had a 0.20 threshold and then
    /// **fell back to the top result anyway** when nothing cleared it, which is how unrelated
    /// tracks ended up playing.
    public var minimumScore: Double = 0.55

    /// How many results to request per attempt.
    public var searchLimit: Int = 15

    public init() {}

    /// Finds the best match on `source`, trying progressively looser queries.
    ///
    /// - Returns: The best acceptable candidate, or `nil` if nothing cleared `minimumScore`.
    public func match(_ target: MatchTarget, on source: any MusicSource) async throws -> MatchResult? {
        let span = CisumSignpost.search.begin("match-song", "\(source.id) \(target.title)")
        defer { CisumSignpost.search.end("match-song", state: span) }

        for (index, query) in queries(for: target).enumerated() {
            if index > 0 {
                // Recorded so the retry rate is visible in Instruments. A source that always needs
                // three attempts is either badly matched to the catalogue or has a broken search.
                CisumSignpost.search.event("match-retry", "\(source.id) attempt \(index + 1)")
            }

            let candidates = try await source.searchTracks(query: query, limit: searchLimit)
            if let best = best(from: candidates, for: target) {
                return best
            }
        }

        PerfLog.warning("No acceptable match for '\(target.title)' by '\(target.artist)' on \(source.id)")
        return nil
    }

    /// Picks the best candidate, or nothing.
    public func best(from candidates: [SourceTrack], for target: MatchTarget) -> MatchResult? {
        // An ISRC agreement is identity, not evidence — no scoring needed.
        if let isrc = target.isrc?.uppercased(), !isrc.isEmpty,
           let exact = candidates.first(where: { $0.isrc?.uppercased() == isrc })
        {
            return MatchResult(
                track: exact,
                score: 1,
                variant: VariantDetector.primary(in: exact.title),
                isExact: true
            )
        }

        let requestedVariants = VariantDetector.detect(in: target.title)

        let scored = candidates.compactMap { candidate -> MatchResult? in
            guard VariantDetector.isAcceptable(
                candidateTitle: candidate.title,
                queryVariants: requestedVariants
            ) else { return nil }

            let score = score(candidate, against: target)
            guard score >= minimumScore else { return nil }

            return MatchResult(
                track: candidate,
                score: score,
                variant: VariantDetector.primary(in: candidate.title),
                isExact: false
            )
        }

        return scored.max { $0.score < $1.score }
    }

    /// Scores a candidate 0...1.
    ///
    /// **Artist is weighted highest and gated.** A karaoke or cover version matches the title
    /// perfectly and the artist not at all, so title-led scoring reliably picks the wrong one —
    /// which is exactly what the previous implementation did. Verifying the artist first is the
    /// single most important rule here.
    func score(_ candidate: SourceTrack, against target: MatchTarget) -> Double {
        let artistScore = max(
            TextNormalizer.tokenOverlap(expected: target.artist, candidate: candidate.artist),
            TextNormalizer.similarity(target.artist, candidate.artist)
        )

        // Hard gate. No amount of title agreement rescues the wrong performer.
        guard artistScore >= 0.5 else { return 0 }

        let titleScore = max(
            TextNormalizer.tokenOverlap(
                expected: TextNormalizer.normalizeStrippingVersions(target.title),
                candidate: TextNormalizer.normalizeStrippingVersions(candidate.title)
            ),
            TextNormalizer.similarity(
                TextNormalizer.normalizeStrippingVersions(target.title),
                TextNormalizer.normalizeStrippingVersions(candidate.title)
            )
        )

        var total = titleScore * 0.45 + artistScore * 0.35

        // Duration is strong corroboration when both sides report it — two recordings of the same
        // work by the same artist within a few seconds are almost certainly the same master.
        if let expected = target.durationSeconds, let actual = candidate.durationSeconds,
           expected > 0, actual > 0
        {
            let delta = abs(expected - actual)
            let durationScore = delta <= 2 ? 1.0 : delta <= 5 ? 0.7 : delta <= 15 ? 0.3 : 0.0
            total += durationScore * 0.20
        } else {
            // Neither rewarded nor punished for being unknown; redistribute to what is known.
            total += (titleScore * 0.45 + artistScore * 0.35) * 0.20 / 0.80
        }

        if let expectedAlbum = target.album, let actualAlbum = candidate.album,
           !expectedAlbum.isEmpty, !actualAlbum.isEmpty
        {
            total += TextNormalizer.similarity(expectedAlbum, actualAlbum) * 0.05
        }

        return min(1, total)
    }

    /// Query attempts, loosest last.
    ///
    /// The retry ladder exists because provider catalogues disagree on script. A Japanese or
    /// Korean title may be indexed in its original script on one service and romanised on another,
    /// so a single query shape fails for a whole category of music.
    ///
    /// - Note: Romanisation is not implemented here yet. `Foundation`'s transliteration handles
    ///   the common cases and belongs behind this seam — the ladder's *shape* is what matters, and
    ///   it degrades to two attempts until then.
    func queries(for target: MatchTarget) -> [String] {
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = target.artist.trimmingCharacters(in: .whitespacesAndNewlines)

        var attempts = ["\(title) \(artist)"]

        // Bare title, for catalogues that index the artist separately and choke on both.
        if !artist.isEmpty {
            attempts.append(title)
        }

        // Version-stripped, for catalogues carrying only the plain release.
        let stripped = TextNormalizer.normalizeStrippingVersions(title)
        if stripped != TextNormalizer.normalize(title), !stripped.isEmpty {
            attempts.append("\(stripped) \(artist)")
        }

        return attempts
    }
}
