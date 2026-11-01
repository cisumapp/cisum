//
//  CandidateRankingPolicy.swift
//  PlaybackCore
//
//  Choosing between the several ways a track can be played. Deterministic, and honest about what is
//  not known.
//

import Foundation
import ProviderSDK

/// A candidate the policy refused, and why.
public struct RejectedCandidate: Sendable, Equatable {
    public let candidate: PlaybackCandidate
    public let reason: RejectionReason
}

/// Why a candidate never entered the ranking.
public enum RejectionReason: Sendable, Equatable {
    /// Known to be a different recording (another performance, cut or version).
    case incompatibleRecording(String)
    /// Not playable in this environment (DRM, entitlement, region, expired).
    case ineligible(String)

    public var description: String {
        switch self {
        case let .incompatibleRecording(detail): "different recording: \(detail)"
        case let .ineligible(detail): "ineligible: \(detail)"
        }
    }
}

/// The result of ranking a candidate set.
public struct CandidateRanking: Sendable, Equatable {
    /// Usable candidates, best first. Deterministic for equal input.
    public let ranked: [PlaybackCandidate]
    /// Candidates excluded by the identity or eligibility gate.
    public let rejected: [RejectedCandidate]

    /// The candidate playback should start from.
    public var selected: PlaybackCandidate? {
        ranked.first
    }

    /// Everything after the selection, in preference order — the fallback ladder.
    public var fallbacks: [PlaybackCandidate] {
        Array(ranked.dropFirst())
    }
}

/// The policy that turns several candidates into one order.
///
/// **This is not a second ranking system.** Quality comparison is delegated to `StreamSelector`,
/// which already owns the arithmetic that maps structured `SourceStream` fields to a preference and
/// is covered by its own tests. What this adds is everything `StreamSelector` cannot answer from a
/// bare stream: whether the candidate is the right recording, whether it may be played at all,
/// whether it is local, who is serving it, and how it is delivered — compared **tier by tier**
/// rather than folded into one opaque score, so no quality advantage can ever outrank a correctness
/// failure.
///
/// The tiers, highest first:
///
/// 1. **Eligibility** — an unplayable candidate is not a candidate.
/// 2. **Identity** — incompatible recordings are rejected; among the rest, stronger evidence wins.
/// 3. **Availability** — a local file, when policy prefers local and the recording is equally
///    established, beats a network fetch.
/// 4. **Quality** — `StreamSelector`'s structured score, then the provenance of those numbers.
/// 5. **Source trust** — first-party over third-party over unknown.
/// 6. **Delivery** — progressive audio over adaptive manifest over muxed video.
/// 7. **Latency** — compared only when both candidates report a measurement.
/// 8. **Source order** — the caller's preference order, when the set spans several sources.
/// 9. **Adapter order** — the always-decisive tie-break.
///
/// Tiers 8 and 9 are the tie-breaks that make the order total, and they sit here deliberately: a
/// candidate set now spans providers (see `PlaybackResolver`), so `adapterIndex` is only unique
/// within one source. Both are strictly *tie*-breakers — they are reached only when two candidates
/// are equal on every dimension above, so neither can override a quality or identity difference.
///
/// Identity sits above availability deliberately. Preferring local media must not be a blanket rule
/// that can surface an unrelated local file over a confidently matched stream; within one recording,
/// local still wins at tier 3.
public struct CandidateRankingPolicy: Sendable {
    /// Owns the quality dimension. Configured by the caller as before.
    public var quality: StreamSelector

    /// Whether a local candidate for an equally established recording is preferred.
    ///
    /// True is the documented default — offline playback should use what is on the device. A caller
    /// that knows the user explicitly asked for a network representation can set it false. It never
    /// overrides identity: see the note above.
    public var prefersLocal: Bool

    public init(quality: StreamSelector = StreamSelector(), prefersLocal: Bool = true) {
        self.quality = quality
        self.prefersLocal = prefersLocal
    }

    /// Ranks a candidate set.
    ///
    /// Pure and order-independent: the input array's order is irrelevant because `adapterIndex` is
    /// the final tie-break, so the same candidates always produce the same order.
    public func rank(_ candidates: [PlaybackCandidate]) -> CandidateRanking {
        var usable: [PlaybackCandidate] = []
        var rejected: [RejectedCandidate] = []

        for candidate in candidates {
            if case let .incompatible(reason) = candidate.identity {
                rejected.append(RejectedCandidate(candidate: candidate, reason: .incompatibleRecording(reason)))
            } else if case let .ineligible(reason) = candidate.eligibility {
                rejected.append(RejectedCandidate(candidate: candidate, reason: .ineligible(reason)))
            } else {
                usable.append(candidate)
            }
        }

        return CandidateRanking(
            ranked: usable.sorted(by: isOrderedBefore),
            rejected: rejected
        )
    }

    /// Whether `lhs` should play before `rhs`.
    ///
    /// A strict total order: every tier falls through on equality and the last one, `adapterIndex`,
    /// is distinct per candidate. That is what makes `sorted(by:)` deterministic regardless of the
    /// algorithm's stability.
    public func isOrderedBefore(_ lhs: PlaybackCandidate, _ rhs: PlaybackCandidate) -> Bool {
        // 1. Eligibility is a gate, so both are eligible here — but order defensively if not.
        if lhs.eligibility.isEligible != rhs.eligibility.isEligible {
            return lhs.eligibility.isEligible
        }

        // 2. Identity — the correctness gate. Stronger evidence wins; a higher bitrate cannot
        //    compensate for a weaker claim on the recording.
        if lhs.identity.rank != rhs.identity.rank {
            return lhs.identity.rank > rhs.identity.rank
        }

        // 3. Local media, when policy allows it to be preferred.
        if prefersLocal, lhs.availability.rank != rhs.availability.rank {
            return lhs.availability.rank > rhs.availability.rank
        }

        // 4. Quality: structured evidence first (`StreamSelector`), then whether the numbers are
        //    provider-reported or measured. `qualityComparableStream` is what keeps a muxed
        //    container's video-inclusive bitrate out of an audio-quality comparison.
        let lhsScore = quality.score(lhs.qualityComparableStream)
        let rhsScore = quality.score(rhs.qualityComparableStream)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.evidence.rank != rhs.evidence.rank {
            return lhs.evidence.rank > rhs.evidence.rank
        }

        // 5. Source trust, from runtime policy.
        if lhs.trust.rank != rhs.trust.rank {
            return lhs.trust.rank > rhs.trust.rank
        }

        // 6. Delivery cost.
        if lhs.transportClass.rank != rhs.transportClass.rank {
            return lhs.transportClass.rank > rhs.transportClass.rank
        }

        // 7. Latency — only when both are known. Unknown is neutral, never punished.
        if let lhsLatency = lhs.latencyMs, let rhsLatency = rhs.latencyMs, lhsLatency != rhsLatency {
            return lhsLatency < rhsLatency
        }

        // 8. Source order. Inside one source every candidate shares it, so this is inert unless the
        //    set spans providers — where it prefers the source the user actually asked for.
        if lhs.sourceOrder != rhs.sourceOrder {
            return lhs.sourceOrder < rhs.sourceOrder
        }

        // 9. Adapter order. Together with source order this is unique, so the order is total.
        return lhs.adapterIndex < rhs.adapterIndex
    }
}
