//
//  PlaybackTimeline.swift
//  Models
//
//  The two lengths a playing track can have, and which one the timeline is measured against.
//

import Foundation

/// Decides which duration the player's timeline is measured against.
///
/// A track has two possible lengths and they are not the same fact:
///
/// - **Canonical** — what the catalogue says. It comes from the search result or the matched provider
///   representation, it is known before anything is fetched, and for a live recording or a
///   misidentified match it can simply be wrong.
/// - **Observed** — what `AVPlayerItem` reports for the file actually loaded. It is the length of the
///   audio being played, and it is unknown until the item is ready.
///
/// The scrubber, the elapsed/total labels, the lock-screen duration and completion detection all
/// measure the *item*, so the timeline is the observed length whenever one is usable, and the
/// canonical length only until the item reports one. Neither is ever invented: unknown, zero,
/// negative, NaN and infinite are not durations, and when neither side is usable the timeline is
/// `nil` — which the UI renders as "length unknown" rather than as "length 0", the value that
/// previously made an unloaded track look like a finished one.
public enum PlaybackTimeline {
    /// A duration in seconds, or `nil` when the value is not a usable length.
    public static func usable(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// The length of the timeline: the observed item duration when it is usable, else the canonical
    /// one when *it* is usable, else `nil` for unknown.
    ///
    /// Observed leads because it describes the audio that exists, not the metadata that was promised.
    /// A wrong canonical duration — a misidentified recording, or a search result whose timestamp
    /// belongs to a different version — is not corrected by keeping a plausible-looking wrong number
    /// on screen; it is corrected by the item's own length replacing it.
    /// - Parameter reported: The length the service states for the exact file playing. Wins over
    ///   `observed` because AVFoundation only *estimates* a fragmented MP4's duration, and that
    ///   estimate has been measured at double the real length.
    public static func duration(canonical: Double, observed: Double?, reported: Double? = nil) -> Double? {
        usable(reported) ?? usable(observed) ?? usable(canonical)
    }
}
