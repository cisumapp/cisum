//
//  PlaybackResolutionPath.swift
//  PlaybackCore
//
//  How a playback stream was obtained — the classification behind "warm" and "cold".
//

import Foundation

/// Which route `PlaybackResolver` took to produce a playable stream.
///
/// These are the documented warm/cold definitions (`PASS-02.5-BASELINE-REPORT.md`) expressed as a
/// type, so the metric that consumes them cannot silently drift from them:
///
///  • `cachedStreamURL` — **warm.** A fresh cached `SongSource` URL was used: zero network calls.
///  • `directProviderID` — **cold.** The track id was known and resolved directly against a source.
///  • `matchedProvider` — **cold.** The track had to be matched on a source first, then resolved.
///
/// An **app launch is not a cold playback request** and is not represented here at all.
public enum PlaybackResolutionPath: String, Sendable, CaseIterable {
    /// Step 1 — a fresh cached stream URL. Warm.
    case cachedStreamURL
    /// Step 2 — direct resolution by a known provider track id. Cold.
    case directProviderID
    /// Step 3 — match on a playable source, then resolve. Cold.
    case matchedProvider

    /// Whether this path is a warm playback-resolution attempt.
    public var isWarm: Bool {
        self == .cachedStreamURL
    }

    /// Whether this path is a cold playback-resolution attempt.
    public var isCold: Bool {
        !isWarm
    }
}

public extension Duration {
    /// The duration in milliseconds as a `Double`, for metric storage.
    var milliseconds: Double {
        Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
