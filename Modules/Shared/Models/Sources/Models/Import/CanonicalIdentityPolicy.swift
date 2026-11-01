//
//  CanonicalIdentityPolicy.swift
//  Models
//
//  The authoritative canonical-identity match policy (decision U-11).
//
//  One policy, applied in one place, so provider-specific matching cannot independently
//  establish canonical identity and a bare title/artist fingerprint can never authorize a merge.
//

import Foundation

/// The single canonical-identity match policy.
///
/// U-11 froze one identity policy: a provider representation matches a canonical `Song` only on
/// established provider identity, a usable matching ISRC, or confident scoring through
/// `CanonicalSongReconciler`. A title/artist fingerprint is candidate-discovery evidence and is
/// never, by itself, sufficient grounds for an irreversible merge.
public enum CanonicalIdentityPolicy {
    // MARK: - ISRC

    /// Whether a raw ISRC is usable as recording-identity evidence.
    ///
    /// A malformed, empty, or wrong-shaped value is treated as **absent** — never as a weak match.
    /// ISRCs are frequently written with hyphens (`US-UM7-16-14169`); separators are ignored before
    /// the shape check.
    public static func isValidISRC(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let compact = raw
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard compact.count == 12 else { return false }

        // CC (country, letters) + XXX (registrant, alphanumeric) + YY (year, digits) + NNNNN (digits)
        return compact.range(of: "^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$", options: .regularExpression) != nil
    }

    // MARK: - Match decision

    /// The evidence that resolved an incoming representation to a canonical record.
    public enum Evidence: Equatable, Sendable {
        /// The provider representation was already bound to this canonical song.
        case establishedBinding(songID: String)
        /// A usable ISRC matched an existing canonical record exactly.
        case matchingISRC(songID: String)
        /// Title/artist/duration/version agreement cleared the confident threshold.
        case confidentScore(songID: String, score: Double)
        /// No evidence was strong enough; the caller must retain separate records or defer.
        case none

        /// The resolved canonical song id, when the evidence identifies one.
        public var songID: String? {
            switch self {
            case let .establishedBinding(songID), let .matchingISRC(songID): songID
            case let .confidentScore(songID, _): songID
            case .none: nil
            }
        }
    }

    /// Resolves which canonical record an incoming representation belongs to.
    ///
    /// Ordering (U-11):
    /// 1. **Established provider binding** — this exact representation is already associated with a
    ///    canonical song, so identity is unambiguous.
    /// 2. **Valid, matching ISRC** — strong recording-identity evidence. A malformed ISRC does not
    ///    qualify, and a version/performance contradiction must have been ruled out by the caller
    ///    before a candidate id is passed here.
    /// 3. **Confident score** — `CanonicalSongReconciler` scoring at or above
    ///    `CanonicalSongReconciler.confidentThreshold` (title + duration + artist, version-gated).
    /// 4. Otherwise `.none` — retain separate records or defer; never merge on a weak fingerprint.
    ///
    /// - Parameters:
    ///   - isrc: The incoming representation's ISRC, if any. Validated here; ignored when malformed.
    ///   - establishedBinding: The canonical song id already bound to this exact provider id pair.
    ///   - isrcMatch: The canonical song id whose ISRC matches, when the caller found one.
    ///   - scoredMatches: Candidate canonical songs with their `CanonicalSongReconciler` scores.
    public static func decide(
        isrc: String?,
        establishedBinding: String?,
        isrcMatch: String?,
        scoredMatches: [(songID: String, score: Double)]
    ) -> Evidence {
        if let establishedBinding, !establishedBinding.isEmpty {
            return .establishedBinding(songID: establishedBinding)
        }

        if isValidISRC(isrc), let isrcMatch, !isrcMatch.isEmpty {
            return .matchingISRC(songID: isrcMatch)
        }

        // Highest clearing score wins. Candidates arrive from an unordered fetch, so when two
        // candidates tie on the top score the tie is broken by ascending `songID` — otherwise the
        // merge target would depend on fetch order and could differ run to run (Pass 2.5 Task A).
        let best = scoredMatches
            .filter { $0.score >= CanonicalSongReconciler.confidentThreshold }
            .max { lhs, rhs in
                lhs.score == rhs.score ? lhs.songID > rhs.songID : lhs.score < rhs.score
            }

        if let best {
            return .confidentScore(songID: best.songID, score: best.score)
        }

        return .none
    }
}
