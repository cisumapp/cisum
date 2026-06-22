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
            return width / 390.0
        }
    }
    
    /// Accessory phases for tab bars and player overlays.
    public enum AccessoryPhase {
        case inline              // tab bar visible, accessory docked above it
        case expanded            // tab bar hidden (scroll), accessory dropped to bottom
        case inlineWithSearch    // inline, a .search role tab is present
        case expandedWithSearch  // expanded, a .search role tab is present
    }

    // MARK: - Accessory Offsets
    //
    // All constants are empirically measured on real iOS 26.5 builds using a
    // UIKit geometry probe that walks the view hierarchy to the actual accessory
    // platter and reads its frame in window coordinates.
    //
    // Measured on 4 devices (notch 375, Dynamic Island 390/402/440), all portrait,
    // all safeBottom = 34:
    //
    //   accessoryHeight : 48 pt  (constant across all widths)
    //   width           : screenWidth - 42 pt  (21 pt each side, constant)
    //   bottomOffset    : 91 pt (inline) | 21 pt (expanded)   from SCREEN bottom
    //
    // IMPORTANT: bottomOffset is measured from the physical screen bottom, NOT
    // the safe-area boundary. Use `bottomInsetFromScreenEdge` with ignoresSafeArea
    // views, and `bottomInsetFromSafeArea` inside safeAreaInset content.
    //
    // Limitations:
    //   • All measured devices share safeBottom = 34. The 91/21 values may or may
    //     not shift on a device with a different safeBottom; no such iOS 26 device
    //     currently exists. Re-measure if one appears.
    //   • Landscape: height 44, width screenWidth - 76, bottomOffset 72.
    //     Not currently implemented — add a landscape axis when needed.
    //   • Search presence does NOT change any metric today; the WithSearch variants
    //     carry identical numbers but are kept for future-proofing.

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
        public var bottomInsetFromScreenEdge: CGFloat { bottomOffset }

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
        ///     (`56 * screenScale`). When `0` (default, iOS 26) the empirically
        ///     measured `91 pt` constant is used instead.
        ///     The iOS 26 brief explicitly states that search presence does NOT
        public init(
            phase: AccessoryPhase,
            screenWidth: CGFloat,
            safeAreaBottom: CGFloat = 0,
            tabBarHeight: CGFloat = 0,
            isSearchExpanded: Bool = false
        ) {
            self.accessoryHeight = 48   // measured — do not scale
            self.sideInset = 21         // measured — do not scale
            self.width = screenWidth - 42
            self.safeAreaBottom = safeAreaBottom

            switch phase {
            case .inline, .inlineWithSearch:
                if tabBarHeight > 0 {
                    // iOS 17/18: compute from real bar height so the accessory
                    // always clears the bar, regardless of search state.
                    // Formula: safeArea + barHeight + 8 pt gap.
                    // e.g. iPhone 14: 34 + 56 + 8 = 98 pt from screen bottom
                    self.bottomOffset = safeAreaBottom + tabBarHeight + 8 + (isSearchExpanded ? -12 : 0)
                } else {
                    // iOS 26: empirically measured constant.
                    // Search presence does NOT change this value (brief §"core finding").
                    self.bottomOffset = 91 + (isSearchExpanded ? -12 : 0)
                }
            case .expanded, .expandedWithSearch:
                // Tab bar hidden: accessory drops to near the home indicator.
                // Same on both iOS 26 (measured) and iOS 17/18.
                self.bottomOffset = 21
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
