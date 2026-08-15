//
//  PlayerMatchedGeometry.swift
//  Player
//
//  Follows AppleMusicStylePlayer by Alexey Vorobyov (MIT, © 2025).
//

import Foundation

/// Identifiers for views that fly between the collapsed and expanded player.
///
/// `matchedGeometryEffect` pairs views by `(id, namespace)`. Both must match, and — critically —
/// only **one** view with a given pair may be in the tree at a time. Two simultaneous sources make
/// SwiftUI pick one arbitrarily, which reads as the artwork jumping rather than flying.
enum PlayerMatchedGeometry: Hashable {
    case artwork
}
