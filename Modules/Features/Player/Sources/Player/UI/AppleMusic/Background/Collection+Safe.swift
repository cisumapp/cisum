//
//  Collection+Safe.swift
//  Player
//
//  Adapted from AppleMusicStylePlayer by Alexey Vorobyov (MIT, © 2025).
//

import Foundation

extension Collection {
    /// Bounds-checked access.
    ///
    /// The imported gradient code indexes a fixed eight colour slots against a palette that may be
    /// shorter, and relies on out-of-range reads returning nil rather than trapping.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
