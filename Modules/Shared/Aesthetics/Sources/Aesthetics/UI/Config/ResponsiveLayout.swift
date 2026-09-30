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

    /// The largest multiplier `desktopScaleFactor` will ever return.
    public static let desktopScaleCeiling: CGFloat = 1.2

    /// Scaling for a macOS window.
    ///
    /// `DeviceSizeClass.scaleFactor(for:)` is normalized to an iPhone and grows without bound,
    /// which is right on a phone (and on iPad, where a wider screen genuinely wants bigger
    /// artwork) but wrong for a desktop window: a 1512pt-wide Mac display yields 3.88×, turning
    /// a 60pt track row into a 232pt one. macOS has no width-driven type ramp to join — a window
    /// can be resized independently of its display — so the multiplier is capped instead.
    ///
    /// Use this for every layout that multiplies a fixed point size by a screen-width scale.
    public static func desktopScaleFactor(for width: CGFloat) -> CGFloat {
        min(width / 390.0, desktopScaleCeiling)
    }

    /// The scale multiplier appropriate to the current platform, given a screen width.
    ///
    /// Prefer this over calling `DeviceSizeClass.scaleFactor` directly, so macOS windows
    /// cannot accidentally inherit the uncapped iPhone ramp.
    public static func scaleFactor(forScreenWidth width: CGFloat) -> CGFloat {
        #if os(macOS)
        desktopScaleFactor(for: width)
        #else
        DeviceSizeClass(width: width).scaleFactor(for: width)
        #endif
    }

    /// The determinable states the system accessory actually has.
    ///
    /// Every field is observable from the main SwiftUI tree, so the state can be
    /// recomputed rather than inferred. Geometry is a pure function of this value
    /// plus screen width — see the measured table in the header below.
    public struct AccessoryState: Equatable, Sendable {
        public enum Orientation: Equatable, Sendable {
            case portrait
            case landscape
        }

        /// Mirrors the system's `TabViewBottomAccessoryPlacement`.
        public enum Placement: Equatable, Sendable {
            /// Tab bar visible, accessory docked above it.
            case inline
            /// Tab bar hidden on scroll, accessory dropped toward the home indicator.
            case minimized
        }

        public var orientation: Orientation
        public var placement: Placement
        /// Whether the search field is actually open. A search-role tab merely
        /// existing does not move the accessory.
        public var searchActive: Bool

        public init(orientation: Orientation, placement: Placement, searchActive: Bool = false) {
            self.orientation = orientation
            self.placement = placement
            self.searchActive = searchActive
        }

        /// Landscape + search is unmeasured and confirmed not to differ, so search
        /// is deliberately ignored there rather than extrapolating portrait deltas.
        public var effectiveSearchActive: Bool {
            orientation == .portrait && searchActive
        }
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
    // Search is keyed on `AccessoryState.searchActive` — the field actually being
    // open. A search-role tab merely existing does not move anything. Search shifts
    // bottomOffset by -7 when inline and +7 when minimized; the flat -12 this
    // replaced was wrong in magnitude and, for the minimized case, in sign.
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
        ///   - state: the resolved accessory state. Compute it in the main SwiftUI
        ///     tree — the overlay window never receives the environment it needs.
        ///   - screenWidth: full screen width in the current orientation. Prefer the
        ///     window scene's coordinate space; `UIScreen.main.bounds` lags rotation.
        ///   - safeAreaBottom: used by the iOS 17/18 derived formula and by
        ///     `bottomInsetFromSafeArea`.
        ///   - tabBarHeight: **iOS 17/18 only** — the real custom bar height
        ///     (`56 * screenScale`). When `0` (default, iOS 26) the measured
        ///     constants are used instead.
        public init(
            state: AccessoryState,
            screenWidth: CGFloat,
            safeAreaBottom: CGFloat = 0,
            tabBarHeight: CGFloat = 0
        ) {
            self.accessoryHeight = 48 // measured — constant in every state
            self.safeAreaBottom = safeAreaBottom

            let inset: CGFloat
            let inlineBottom: CGFloat
            let minimizedBottom: CGFloat

            switch (state.orientation, state.effectiveSearchActive) {
            case (.portrait, false):
                inset = 21
                inlineBottom = 91
                minimizedBottom = 21
            case (.portrait, true):
                inset = 28
                inlineBottom = 84
                minimizedBottom = 28
            case (.landscape, _):
                inset = 38
                inlineBottom = 70
                minimizedBottom = 18
            }

            self.sideInset = inset
            self.width = screenWidth - inset * 2

            switch state.placement {
            case .inline:
                if tabBarHeight > 0 {
                    // iOS 17/18: derive from the real custom bar height so the
                    // accessory always clears it. Note this lands ~7 pt lower than
                    // native iOS 26 (iPhone 14: 34 + 56 + 8 = 98 vs measured 91) —
                    // closing that gap needs the custom bar resized, not a constant.
                    self.bottomOffset = safeAreaBottom + tabBarHeight + 8
                        + (state.effectiveSearchActive ? -7 : 0)
                } else {
                    self.bottomOffset = inlineBottom
                }
            case .minimized:
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
