@testable import Aesthetics
import Foundation
import Testing

// Values below are on-device measurements from TabBarGeometryProbe (DEBUG), taken
// on iPhone 12 mini (375x812) and iPhone 14 (390x844), both safeBottom 34.
// Both devices produced identical platter geometry, so these are asserted as exact.

private let miniWidth: CGFloat = 375
private let fourteenWidth: CGFloat = 390

// Landscape screen width is the portrait height.
private let miniLandscapeWidth: CGFloat = 812
private let fourteenLandscapeWidth: CGFloat = 844

private func portrait(
    _ placement: ResponsiveLayout.AccessoryState.Placement,
    search: Bool = false
) -> ResponsiveLayout.AccessoryState {
    .init(orientation: .portrait, placement: placement, searchActive: search)
}

private func landscape(
    _ placement: ResponsiveLayout.AccessoryState.Placement,
    search: Bool = false
) -> ResponsiveLayout.AccessoryState {
    .init(orientation: .landscape, placement: placement, searchActive: search)
}

// MARK: - Portrait

@Test func portraitInlineMatchesMeasuredGeometry() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            state: portrait(.inline),
            screenWidth: width,
            safeAreaBottom: 34
        )

        #expect(offsets.accessoryHeight == 48)
        #expect(offsets.sideInset == 21)
        #expect(offsets.width == width - 42)
        #expect(offsets.bottomOffset == 91)
    }
}

@Test func portraitMinimizedDropsToTwentyOne() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            state: portrait(.minimized),
            screenWidth: width,
            safeAreaBottom: 34
        )

        #expect(offsets.sideInset == 21)
        #expect(offsets.width == width - 42)
        #expect(offsets.bottomOffset == 21)
    }
}

// MARK: - Portrait + search

/// Search narrows the pill and lifts it. The previous model applied a flat -12 to
/// bottomOffset and left inset/width alone; measurement says inset 28, width -56,
/// and bottom -7.
@Test func searchNarrowsAndLiftsWhenInline() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            state: portrait(.inline, search: true),
            screenWidth: width,
            safeAreaBottom: 34
        )

        #expect(offsets.sideInset == 28)
        #expect(offsets.width == width - 56)
        #expect(offsets.bottomOffset == 84)
    }
}

/// The sign flips when minimized: 21 -> 28, not 21 -> 9 as a flat -12 would give.
@Test func searchPushesDownWhenMinimized() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            state: portrait(.minimized, search: true),
            screenWidth: width,
            safeAreaBottom: 34
        )

        #expect(offsets.sideInset == 28)
        #expect(offsets.width == width - 56)
        #expect(offsets.bottomOffset == 28)
    }
}

/// Only an open search field moves the accessory. A search-role tab merely existing
/// is not represented in the state at all, so this asserts the default.
@Test func searchInactiveMatchesPlainPortrait() {
    let inactive = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.inline, search: false),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )
    let plain = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.inline),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(inactive == plain)
}

// MARK: - Landscape

@Test func landscapeUsesWiderInsetAndLowerOffsets() {
    for width in [miniLandscapeWidth, fourteenLandscapeWidth] {
        let inline = ResponsiveLayout.AccessoryOffsets(
            state: landscape(.inline),
            screenWidth: width,
            safeAreaBottom: 20
        )

        #expect(inline.accessoryHeight == 48)
        #expect(inline.sideInset == 38)
        #expect(inline.width == width - 76)
        #expect(inline.bottomOffset == 70)

        let minimized = ResponsiveLayout.AccessoryOffsets(
            state: landscape(.minimized),
            screenWidth: width,
            safeAreaBottom: 20
        )

        #expect(minimized.sideInset == 38)
        #expect(minimized.bottomOffset == 18)
    }
}

/// Landscape + search is unmeasured, so search must be ignored there rather than
/// extrapolating the portrait deltas. Locks that deliberate choice.
@Test func landscapeIgnoresSearchBecauseItIsUnmeasured() {
    let searching = ResponsiveLayout.AccessoryOffsets(
        state: landscape(.inline, search: true),
        screenWidth: fourteenLandscapeWidth,
        safeAreaBottom: 20
    )
    let notSearching = ResponsiveLayout.AccessoryOffsets(
        state: landscape(.inline),
        screenWidth: fourteenLandscapeWidth,
        safeAreaBottom: 20
    )

    #expect(searching == notSearching)
    #expect(searching.sideInset == 38)
    #expect(searching.bottomOffset == 70)
}

// MARK: - State semantics

@Test func effectiveSearchActiveIsPortraitOnly() {
    #expect(portrait(.inline, search: true).effectiveSearchActive == true)
    #expect(portrait(.inline, search: false).effectiveSearchActive == false)
    #expect(landscape(.inline, search: true).effectiveSearchActive == false)
    #expect(landscape(.inline, search: false).effectiveSearchActive == false)
}

// MARK: - iOS 17/18 custom-bar path

/// Passing a tabBarHeight switches to the derived formula for the hand-rolled bar.
/// It intentionally lands ~7pt below native (34 + 56 + 8 = 98 vs 91) because the
/// custom bar is a different height; closing that needs the bar resized.
@Test func customBarPathDerivesFromBarHeight() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.inline),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        tabBarHeight: 56
    )

    #expect(offsets.bottomOffset == 98)

    let searching = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.inline, search: true),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        tabBarHeight: 56
    )

    #expect(searching.bottomOffset == 91) // 98 - 7
}

/// Minimized ignores tabBarHeight entirely — the bar is hidden, so there is
/// nothing to clear.
@Test func customBarPathIgnoresBarHeightWhenMinimized() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.minimized),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        tabBarHeight: 56
    )

    #expect(offsets.bottomOffset == 21)
}

// MARK: - Derived accessors

@Test func bottomInsetFromSafeAreaIsScreenRelative() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.inline),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(offsets.bottomInsetFromScreenEdge == 91)
    #expect(offsets.bottomInsetFromSafeArea == 91 - 34)
}

/// The 4pt clamp stops the accessory sliding under the home indicator when the
/// offset is smaller than the safe-area inset.
@Test func bottomInsetFromSafeAreaClampsAtFour() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        state: portrait(.minimized),
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(offsets.bottomOffset == 21) // below safeAreaBottom
    #expect(offsets.bottomInsetFromSafeArea == 4)
}
