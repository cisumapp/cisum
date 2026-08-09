import Foundation
import Testing
@testable import Aesthetics

// Values below are on-device measurements from TabBarGeometryProbe (DEBUG), taken
// on iPhone 12 mini (375x812) and iPhone 14 (390x844), both safeBottom 34.
// Both devices produced identical platter geometry, so these are asserted as exact.

private let miniWidth: CGFloat = 375
private let fourteenWidth: CGFloat = 390

// MARK: - Portrait

@Test func portraitInlineMatchesMeasuredGeometry() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            phase: .inline,
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
    let offsets = ResponsiveLayout.AccessoryOffsets(
        phase: .expanded,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(offsets.sideInset == 21)
    #expect(offsets.width == fourteenWidth - 42)
    #expect(offsets.bottomOffset == 21)
}

// MARK: - Portrait + search

/// Search narrows the pill and lifts it. The previous model applied a flat -12 to
/// bottomOffset and left inset/width alone; measurement says inset 28, width -56,
/// and bottom -7.
@Test func searchNarrowsAndLiftsWhenInline() {
    for width in [miniWidth, fourteenWidth] {
        let offsets = ResponsiveLayout.AccessoryOffsets(
            phase: .inlineWithSearch,
            screenWidth: width,
            safeAreaBottom: 34,
            isSearchExpanded: true
        )

        #expect(offsets.sideInset == 28)
        #expect(offsets.width == width - 56)
        #expect(offsets.bottomOffset == 84)
    }
}

/// The sign flips when minimized: 21 -> 28, not 21 -> 9 as a flat -12 would give.
@Test func searchPushesDownWhenMinimized() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        phase: .expandedWithSearch,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        isSearchExpanded: true
    )

    #expect(offsets.sideInset == 28)
    #expect(offsets.bottomOffset == 28)
}

/// A search-role tab merely existing must not move anything — only an open field does.
@Test func searchTabPresenceAloneDoesNotChangeGeometry() {
    let present = ResponsiveLayout.AccessoryOffsets(
        phase: .inlineWithSearch,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        isSearchExpanded: false
    )
    let absent = ResponsiveLayout.AccessoryOffsets(
        phase: .inline,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(present == absent)
}

// MARK: - Landscape

@Test func landscapeUsesWiderInsetAndLowerOffsets() {
    // Landscape screen width is the portrait height.
    for width in [CGFloat(812), CGFloat(844)] {
        let inline = ResponsiveLayout.AccessoryOffsets(
            phase: .inline,
            screenWidth: width,
            safeAreaBottom: 20,
            isLandscape: true
        )

        #expect(inline.accessoryHeight == 48)
        #expect(inline.sideInset == 38)
        #expect(inline.width == width - 76)
        #expect(inline.bottomOffset == 70)

        let minimized = ResponsiveLayout.AccessoryOffsets(
            phase: .expanded,
            screenWidth: width,
            safeAreaBottom: 20,
            isLandscape: true
        )

        #expect(minimized.bottomOffset == 18)
    }
}

/// Landscape + search is unmeasured, so search must be ignored there rather than
/// extrapolating the portrait deltas. Locks that deliberate choice.
@Test func landscapeIgnoresSearchBecauseItIsUnmeasured() {
    let searching = ResponsiveLayout.AccessoryOffsets(
        phase: .inlineWithSearch,
        screenWidth: 844,
        safeAreaBottom: 20,
        isSearchExpanded: true,
        isLandscape: true
    )

    #expect(searching.sideInset == 38)
    #expect(searching.width == 844 - 76)
    #expect(searching.bottomOffset == 70)
}

// MARK: - iOS 17/18 custom-bar path

/// Passing a tabBarHeight switches to the derived formula for the hand-rolled bar.
/// It intentionally lands ~7pt below native (34 + 56 + 8 = 98 vs 91) because the
/// custom bar is a different height; closing that needs the bar resized.
@Test func customBarPathDerivesFromBarHeight() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        phase: .inline,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        tabBarHeight: 56
    )

    #expect(offsets.bottomOffset == 98)

    let searching = ResponsiveLayout.AccessoryOffsets(
        phase: .inline,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34,
        tabBarHeight: 56,
        isSearchExpanded: true
    )

    #expect(searching.bottomOffset == 91) // 98 - 7
}

// MARK: - Derived accessors

@Test func bottomInsetFromSafeAreaIsScreenRelative() {
    let offsets = ResponsiveLayout.AccessoryOffsets(
        phase: .inline,
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
        phase: .expanded,
        screenWidth: fourteenWidth,
        safeAreaBottom: 34
    )

    #expect(offsets.bottomOffset == 21) // below safeAreaBottom
    #expect(offsets.bottomInsetFromSafeArea == 4)
}
