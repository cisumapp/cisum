//
//  ResponsiveLayout.swift
//  cisum
//

import SwiftUI

/// Universally available device sizing and responsive layout configuration.
public enum ResponsiveLayout {
    /// Size classes based on device screen width.
    public enum DeviceSizeClass {
        case compact
        case standard
        case large

        public init(width: CGFloat) {
            if width < 390 {
                self = .compact
            } else if width < 414 {
                self = .standard
            } else {
                self = .large
            }
        }

        /// A continuous scaling multiplier normalized to an iPhone 14 / 16 (390pt width).
        /// Useful when you need a smooth mathematical scaling instead of stepped classes.
        public func scaleFactor(for width: CGFloat) -> CGFloat {
            width / 390.0
        }
    }

    /// Accessory phases for tab bars and player overlays.
    public enum AccessoryPhase {
        case inline // tab bar visible, accessory docked above it
        case expanded // tab bar hidden (scroll), accessory dropped to bottom
        case inlineWithSearch // inline, a .search role tab is present
        case expandedWithSearch // expanded, a .search role tab is present
    }

    // MARK: - Accessory Offsets

    //
    // All constants are empirically measured on real iOS 26 builds by
    // `TabBarGeometryProbe` (DEBUG, Tabbar/Debug/), which reads the live
    // `.tabViewBottomAccessory` frame via `onGeometryChange` and grows it by the
    // 1.5 pt platter inset. See that file for the measurement method.
    //
    // Measured on iPhone 12 mini (375x812, safeTop 50) and iPhone 14 (390x844,
    // safeTop 47), both safeBottom = 34. Every derived platter value landed on an
    // exact integer on both devices:
    //
    //   accessoryHeight : 48 pt   in every state, both orientations
    //
    //   portrait            inset 21  width screenWidth - 42   inline 91  minimized 21
    //   portrait + search   inset 28  width screenWidth - 56   inline 84  minimized 28
    //   landscape           inset 38  width screenWidth - 76   inline 70  minimized 18
    //
    // Search is keyed on `isSearchExpanded` (the field is actually open), NOT on
    // the `AccessoryPhase` WithSearch variants — those only mean "a search-role tab
    // exists", which does not move anything. Search shifts bottomOffset by -7 when
    // inline and +7 when minimized; the previous flat -12 was wrong in magnitude
    // and, for the minimized case, in sign.
    //
    // IMPORTANT: bottomOffset is measured from the physical screen bottom, NOT
    // the safe-area boundary. Use `bottomInsetFromScreenEdge` with ignoresSafeArea
    // views, and `bottomInsetFromSafeArea` inside safeAreaInset content.
    //
    // Limitations:
    //   • Both measured devices share safeBottom = 34, so these values are
    //     confirmed constant across widths and top insets but cannot be
    //     distinguished from a function of a 34 pt bottom inset. Every iOS 26
    //     iPhone with a notch or Dynamic Island is 34. Re-measure if a
    //     home-button device ever runs iOS 26.
    //   • Landscape + search is NOT measured. Landscape deliberately ignores
    //     search rather than extrapolating the portrait deltas — a 7 pt error in a
    //     rare state beats inventing an unverified number.

    /// Computed offsets and dimensions for accessory overlays (like the mini-player).
    /// Initialise with the real `safeAreaBottom` from a GeometryReader for
    /// pixel-perfect placement on every device.
    public struct AccessoryOffsets: Equatable {
        // MARK: Stored

        /// Height of the accessory pill (48 pt portrait — measured constant).
        public let accessoryHeight: CGFloat
        /// Width of the accessory pill (screenWidth − 42 pt — measured constant).
        public let width: CGFloat
        /// Per-side horizontal inset (21 pt — measured constant).
        public let sideInset: CGFloat
        /// Distance from the physical screen bottom to the accessory's bottom edge.
        /// 91 pt when the tab bar is visible; 21 pt when hidden.
        public let bottomOffset: CGFloat
        /// Safe-area bottom inset passed in from the caller's GeometryReader.
        public let safeAreaBottom: CGFloat

        // MARK: Derived

        /// Use this as `.padding(.bottom, X)` on views that call `.ignoresSafeArea()`.
        /// The content's frame extends to the physical screen edge, so `bottomOffset`
        /// directly positions the accessory the correct distance from the bottom.
        public var bottomInsetFromScreenEdge: CGFloat {
            bottomOffset
        }

        /// Use this as `.padding(.bottom, X)` inside a `safeAreaInset(edge: .bottom)`
        /// ZStack. The inset's origin is the safe-area boundary (safeAreaBottom above
        /// the physical screen edge), so we subtract that to stay screen-relative.
        /// Clamped to 4 pt so the accessory never overlaps the home indicator entirely.
        public var bottomInsetFromSafeArea: CGFloat {
            max(bottomOffset - safeAreaBottom, 4)
        }

        // MARK: Init

        /// - Parameters:
        ///   - phase: The current tab bar / search phase.
        ///   - screenWidth: `UIScreen.main.bounds.width` — do NOT use a GeometryProxy
        ///     inside the tab/safe-area region; it reports a reduced height and
        ///     will produce wrong measurements.
        ///   - safeAreaBottom: `proxy.safeAreaInsets.bottom` from an outer GeometryReader.
        ///   - tabBarHeight: **iOS 17/18 only** — pass the actual custom bar height
        ///     (`56 * screenScale`). When `0` (default, iOS 26) the measured
        ///     constants are used instead.
        ///   - isSearchExpanded: whether the search field is actually open. This,
        ///     not the phase's WithSearch variant, is what moves the accessory.
        ///   - isLandscape: drive from `verticalSizeClass == .compact`, which changes
        ///     in lockstep with layout. Do not derive from `UIScreen.main.bounds`,
        ///     which lags rotation.
        public init(
            phase: AccessoryPhase,
            screenWidth: CGFloat,
            safeAreaBottom: CGFloat = 0,
            tabBarHeight: CGFloat = 0,
            isSearchExpanded: Bool = false,
            isLandscape: Bool = false
        ) {
            self.accessoryHeight = 48 // measured — constant in every state
            self.safeAreaBottom = safeAreaBottom

            // Landscape + search is unmeasured, so landscape ignores search rather
            // than extrapolating the portrait deltas. See the header note.
            let searchActive = isSearchExpanded && !isLandscape

            let inset: CGFloat
            let inlineBottom: CGFloat
            let minimizedBottom: CGFloat

            switch (isLandscape, searchActive) {
            case (false, false):
                inset = 21
                inlineBottom = 91
                minimizedBottom = 21
            case (false, true):
                inset = 28
                inlineBottom = 84
                minimizedBottom = 28
            case (true, _):
                inset = 38
                inlineBottom = 70
                minimizedBottom = 18
            }

            self.sideInset = inset
            self.width = screenWidth - inset * 2

            switch phase {
            case .inline, .inlineWithSearch:
                if tabBarHeight > 0 {
                    // iOS 17/18: derive from the real custom bar height so the
                    // accessory always clears it. Note this lands ~7 pt lower than
                    // native iOS 26 (iPhone 14: 34 + 56 + 8 = 98 vs measured 91) —
                    // closing that gap needs the custom bar resized, not a constant.
                    self.bottomOffset = safeAreaBottom + tabBarHeight + 8 + (searchActive ? -7 : 0)
                } else {
                    self.bottomOffset = inlineBottom
                }
            case .expanded, .expandedWithSearch:
                // Tab bar hidden: accessory drops toward the home indicator.
                self.bottomOffset = minimizedBottom
            }
        }
    }

    /// Sizing constants for the Vinyl player UI, dynamically proportional to the screen width.
    public struct VinylSizes {
        public let heroDiskSize: CGFloat
        public let sideDiskSize: CGFloat
        public let sideDiskOffsetPrevious: CGFloat
        public let sideDiskOffsetNext: CGFloat
        public let sideSlotWidth: CGFloat
        public let sideSlotHeight: CGFloat
        public let sideLabelInset: CGFloat
        public let sideLabelTopInset: CGFloat
        public let mainVStackOffsetY: CGFloat

        public init(screenWidth: CGFloat) {
            self.heroDiskSize = screenWidth * 2.75
            self.sideDiskSize = screenWidth * 0.5

            self.sideDiskOffsetPrevious = screenWidth * -0.15
            self.sideDiskOffsetNext = screenWidth * 0.15

            // The slot is the fixed box each side label is pinned inside.
            // Its leading/trailing edge is the constant reference the label hangs off.
            self.sideSlotWidth = screenWidth * 0.45
            self.sideSlotHeight = screenWidth * 0.5

            // Constant gap from the slot edge — independent of title length.
            self.sideLabelInset = screenWidth * 0.04
            self.sideLabelTopInset = screenWidth * 0.1

            self.mainVStackOffsetY = screenWidth * 0.09
        }
    }
}
