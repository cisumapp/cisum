//
//  PlayerZoomID.swift
//  Player
//

import Foundation

/// Identifies the view the player zooms out of.
///
/// `matchedTransitionSource(id:in:)` and `navigationTransition(.zoom(sourceID:in:))` pair by
/// `(id, namespace)`, and **only one live view may carry a given pair at a time** — two sources
/// make the system pick one arbitrarily, which reads as the player jumping rather than zooming.
///
/// A typed value rather than the reference project's bare `"MINIPLAYER"` string, so the two ends
/// cannot drift apart silently.
public enum PlayerZoomID: Hashable, Sendable {
    /// The collapsed mini player — the accessory on iOS 26, the pill on iOS 17/18.
    case miniPlayer
}
