//
//  PlayerPresentationController.swift
//  Player
//
//  Whether the player is expanded. Read by more views than anything else in the package.
//

import Observation
import SwiftUI
import Utilities

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
        set(true)
    }

    public func collapse() {
        guard isExpanded else { return }
        set(false)
    }

    public func toggle() {
        set(!isExpanded)
    }

    /// Animated only on iOS 17/18, where the overlay-window player springs open from this change; the
    /// ~20 song-tap call sites go through here and the player jumped open without it. On iOS 26 the
    /// zoom cover is UIKit's transition, and wrapping this in `withAnimation` broke it — it stays a
    /// plain set, as it always was there.
    private func set(_ expanded: Bool) {
        #if os(iOS)
        if #unavailable(iOS 26.0) {
            withAnimation(.playerExpandAnimation) { isExpanded = expanded }
            return
        }
        #endif
        isExpanded = expanded
    }
}
