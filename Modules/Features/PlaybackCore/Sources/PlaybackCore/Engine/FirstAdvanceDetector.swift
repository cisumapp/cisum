//
//  FirstAdvanceDetector.swift
//  PlaybackCore
//
//  The single condition behind the first-time-advancing proxy.
//

import Foundation

/// Decides whether a playback time sample is the *first* evidence that the tracked item has begun
/// advancing.
///
/// This is deliberately the only place the condition lives, so the engine and its tests agree on
/// what "first advancement" means.
///
/// **It is a proxy, not proof of audible output.** A sample with advancing time proves the player
/// started rendering for the tracked item; it does not prove sound left the speaker. The metric
/// built on it is named for what it actually measures.
public enum FirstAdvanceDetector {
    /// Whether this sample qualifies as the first advancement.
    ///
    /// - Parameters:
    ///   - seconds: The item's current time from the periodic observer. Non-finite values (which
    ///     `AVPlayer` can report before an item is ready) never qualify.
    ///   - isPlaying: Whether the player is actively playing — not merely loaded or buffering.
    ///   - alreadyReported: Whether an advancement was already reported for this item.
    public static func qualifies(seconds: Double, isPlaying: Bool, alreadyReported: Bool) -> Bool {
        !alreadyReported && isPlaying && seconds.isFinite && seconds > 0
    }
}
