//
//  PlayerTheme.swift
//  Player
//

#if os(iOS)
import SwiftUI

/// A complete visual treatment for the player.
///
/// A theme supplies the three views that make up the player's appearance. It supplies **whole
/// views, not individual elements** — a theme that could only restyle pieces would have to keep
/// its spacing and proportions in agreement with every other theme, and any mismatch would show.
/// Owning the entire expanded view means a theme is internally consistent by construction.
///
/// What a theme does **not** control is behaviour. Expansion, the pan gesture, the window-stacking
/// animation, the offsets, and the presentation shell — `.universalOverlay` on iOS 17/18,
/// `tabViewBottomAccessory` on 26+ — all live in `ExpandablePlayer` and `iOSTabView` and are
/// identical whichever theme is selected. Picking a theme changes how the player looks, never how
/// it opens or dismisses.
@MainActor
public protocol PlayerTheme: Sendable {
    associatedtype Background: View
    associatedtype Mini: View
    associatedtype Expanded: View

    /// Fills the whole player, behind everything else.
    ///
    /// - Parameter collapsedHeight: Height of the collapsed pill, so a theme can size a gradient
    ///   or artwork blur to the mini player rather than the full screen while collapsed.
    @ViewBuilder
    func background(expanded: Bool, fullyExpanded: Bool, collapsedHeight: CGFloat) -> Background

    /// The collapsed pill.
    ///
    /// Only used on iOS 17/18. iOS 26 has a real `tabViewBottomAccessory` acting as the collapsed
    /// player, and drawing a second one produced a visible two-layer handoff.
    @ViewBuilder
    func miniPlayer(expanded: Binding<Bool>, namespace: Namespace.ID) -> Mini

    /// The full-screen player.
    @ViewBuilder
    func expanded(expanded: Bool, size: CGSize, namespace: Namespace.ID) -> Expanded
}

/// The themes that ship with the app.
///
/// A raw-value enum rather than a registry: themes are compiled in, the set is known at build
/// time, and the raw value is what persists in `UserDefaults`. Renaming a case would orphan a
/// stored preference, so the raw values are fixed even if the display names change.
public enum PlayerThemeID: String, CaseIterable, Sendable, Identifiable {
    /// cisum's own look — the spinning vinyl.
    case `default`

    // Adding a theme is three steps and nothing else:
    //
    //   1. Write a type conforming to `PlayerTheme` — three views: background, miniPlayer,
    //      expanded. `DefaultPlayerTheme` is the worked example, and it is a thin wrapper: every
    //      view it returns already existed, which is what proves the seam is in the right place.
    //   2. Add a case here, plus its `displayName` and `summary`.
    //   3. Add the case to the three switches in `PlayerThemeRenderer`. The compiler will tell
    //      you exactly where — that is why the renderer switches rather than storing a protocol
    //      existential.
    //
    // The Settings picker iterates `allCases`, so a new theme appears there with no further work.

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .default: "Vinyl"
        }
    }

    public var summary: String {
        switch self {
        case .default: "A spinning record with the queue either side."
        }
    }
}
#endif
