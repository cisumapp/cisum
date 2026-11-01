//
//  FallbackLadder.swift
//  PlaybackCore
//
//  What to try after the chosen candidate fails, and when to stop trying.
//

import Foundation

/// The alternatives for one playback request, in preference order, plus the one bounded
/// re-resolve that follows when they run out.
///
/// Extracted from `PlayerViewModel` for one reason: the retry bound was **not** actually bounded
/// there. The flag was cleared by the very `start(ref)` call the retry path used, so a track whose
/// resolve kept succeeding while playback kept failing re-resolved forever. Here the ladder is
/// replaced by each resolve (`replaceCandidates`) but the retry allowance is not, so the sequence
/// is finite: every remaining candidate once, then one fresh resolve, then stop.
///
/// Pure and `Sendable`, so the termination property is tested rather than asserted in a comment.
public struct FallbackLadder: Sendable {
    /// The candidates after the selected one, best first.
    private var remaining: [PlaybackCandidate]

    /// The candidate playback started from, for diagnostics.
    public private(set) var startedFrom: PlaybackCandidate?

    /// Whether the one permitted fresh resolve has been used for the current failure episode.
    private var hasUsedResolveRetry = false

    /// An empty ladder — nothing resolved yet, no retry used.
    public init() {
        self.remaining = []
        self.startedFrom = nil
    }

    /// A ladder over a ranked candidate list. `candidates` must be best-first; the first is what
    /// playback starts from and the rest are the fallbacks.
    public init(candidates: [PlaybackCandidate]) {
        self.remaining = Array(candidates.dropFirst())
        self.startedFrom = candidates.first
    }

    /// How many fallbacks are still untried.
    public var remainingCount: Int {
        remaining.count
    }

    /// Whether a fresh resolve may still be attempted for this failure episode.
    public var canRetryResolve: Bool {
        !hasUsedResolveRetry
    }

    /// Replaces the candidate set after a resolve.
    ///
    /// Deliberately does **not** reset the resolve-retry allowance: a retry that re-resolves and
    /// fails again must not restore its own right to retry, which is the loop this type exists to
    /// prevent.
    public mutating func replaceCandidates(_ candidates: [PlaybackCandidate]) {
        remaining = Array(candidates.dropFirst())
        startedFrom = candidates.first
    }

    /// The next fallback to try, or `nil` when the ladder is exhausted.
    public mutating func next() -> PlaybackCandidate? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }

    /// Consumes the one permitted fresh resolve.
    ///
    /// - Returns: `true` the first time in a failure episode, `false` afterwards — which is what
    ///   terminates the sequence.
    public mutating func beginResolveRetry() -> Bool {
        guard !hasUsedResolveRetry else { return false }
        hasUsedResolveRetry = true
        return true
    }

    /// Clears everything for a new playback request.
    public mutating func reset() {
        self = FallbackLadder()
    }
}
