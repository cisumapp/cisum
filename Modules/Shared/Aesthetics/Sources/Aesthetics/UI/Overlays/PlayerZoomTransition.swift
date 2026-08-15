//
//  PlayerZoomTransition.swift
//  Aesthetics
//
//  Mechanism follows AppleMusicBottombarSwiftUI by Ahmet Bostancıklıoğlu.
//

#if os(iOS)
import SwiftUI

/// Identifies the view the player zooms out of.
///
/// `matchedTransitionSource(id:in:)` and `navigationTransition(.zoom(sourceID:in:))` pair by
/// `(id, namespace)`, and **only one live view may carry a given pair at a time** — two sources
/// make the system pick one arbitrarily, which reads as the player jumping rather than zooming.
///
/// A typed value rather than the reference project's bare `"MINIPLAYER"` string, so the two ends
/// of the transition cannot drift apart silently.
public enum PlayerZoomID: Hashable, Sendable {
    /// The collapsed mini player — the `tabViewBottomAccessory` on iOS 26.
    case miniPlayer
}

public extension View {
    /// Marks this view as the thing the player zooms out of.
    ///
    /// Applied only on the iOS 26 path, where the accessory *is* the collapsed player. On
    /// iOS 17/18 the overlay pill plays that role and the transition is hand-rolled, so marking a
    /// source there would create a second live source for the same id.
    @ViewBuilder
    func playerZoomSource(in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            matchedTransitionSource(id: PlayerZoomID.miniPlayer, in: namespace)
        } else {
            self
        }
    }

    /// Presents `content` full-screen with the system zoom transition, on iOS 26 and later.
    ///
    /// A no-op below iOS 26, where `.universalOverlay` presents the player instead. This lives
    /// beside `UniversalOverlay` deliberately: they are the two halves of the same decision, and
    /// putting them together makes it obvious that exactly one runs per OS version.
    ///
    /// Swipe-down dismissal is interactive and comes from the system — the hand-rolled path needs
    /// a `PanGesture` to achieve the same thing.
    @ViewBuilder
    func playerZoomCover(
        isPresented: Binding<Bool>,
        in namespace: Namespace.ID,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        if #available(iOS 26.0, *) {
            fullScreenCover(isPresented: isPresented) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Pairs with `playerZoomSource`. Applied to the presented content itself so
                    // the animation lands on the player rather than an invisible container.
                    .navigationTransition(.zoom(sourceID: PlayerZoomID.miniPlayer, in: namespace))
            }
        } else {
            self
        }
    }
}
#endif
