//
//  PlayerPresentationController.swift
//  Player
//
//  Whether the player is expanded. Read by more views than anything else in the package.
//

import Observation
import SwiftUI

/// Owns the mini/expanded player presentation state.
///
/// Eleven views across seven feature modules read this, almost all of them via
/// `@Environment(PlayerPresentationController.self)`, so `@Observable` is load-bearing.
///
/// It stays deliberately tiny: one boolean and the verbs to change it. Presentation state is read
/// during layout by half the app, so anything else living here would be read during layout by half
/// the app too.
@MainActor
@Observable
public final class PlayerPresentationController {
    /// Whether the full-screen player is showing.
    ///
    /// Settable and bindable — `RootView` drives it with `$presentation.isExpanded`.
    public var isExpanded: Bool

    public init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    public func expand() {
        guard !isExpanded else { return }
        isExpanded = true
    }

    public func collapse() {
        guard isExpanded else { return }
        isExpanded = false
    }

    public func toggle() {
        isExpanded.toggle()
    }
}
