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

    /// Computed offsets and dimensions for accessory overlays (like the mini-player).
    /// Pass `safeAreaBottom` from a GeometryReader so positioning is pixel-perfect.
    public struct AccessoryOffsets: Equatable {
        /// The height of the mini-player accessory pill.
        public let accessoryHeight: CGFloat
        /// The full-width minus the horizontal insets.
        public let width: CGFloat
        /// The horizontal inset on each side.
        public let sideInset: CGFloat
        /// The native tab bar height (only present when the bar is visible).
        public let tabBarHeight: CGFloat
        /// The device safe-area bottom inset.
        public let safeAreaBottom: CGFloat

        /// Distance from the bottom of the **screen** to the bottom edge of the accessory view.
        /// Equivalent to: safe area + tab bar (when visible) + gap above bar.
        public var bottomInsetFromScreenEdge: CGFloat {
            safeAreaBottom + tabBarHeight + 8
        }

        public init(phase: AccessoryPhase, screenWidth: CGFloat, safeAreaBottom: CGFloat = 0) {
            let scale = DeviceSizeClass(width: screenWidth).scaleFactor(for: screenWidth)

            self.accessoryHeight = 48 * scale
            self.sideInset = 21 * scale
            self.width = screenWidth - (self.sideInset * 2)
            self.safeAreaBottom = safeAreaBottom

            // iOS 26 Liquid Glass tab bar sits at 49pt + safe area.
            // On iOS 17/18 the custom bar is 56pt. We use the phase to know which applies.
            switch phase {
            case .inline, .inlineWithSearch:
                // Tab bar is visible – accessory floats just above it.
                self.tabBarHeight = 56 * scale
            case .expanded, .expandedWithSearch:
                // Tab bar is hidden – accessory drops to just above the home indicator.
                self.tabBarHeight = 0
            }
        }
    }
    
    /// Sizing constants for the Vinyl player UI, dynamically proportional to the screen width.
    public struct VinylSizes {
        public let heroDiskSize: CGFloat
        public let sideDiskSize: CGFloat
        public let sideDiskOffsetPrevious: CGFloat
        public let sideDiskOffsetNext: CGFloat
        public let sideLabelOffsetPrevious: CGSize
        public let sideLabelOffsetNext: CGSize
        public let mainVStackOffsetY: CGFloat
        
        public init(screenWidth: CGFloat) {
            // Use clean proportional multipliers rather than scaling hardcoded guesstimates.
            // 2.75 roughly matches the original 1080/390 ratio
            self.heroDiskSize = screenWidth * 2.75
            
            // 0.5 roughly matches the original 200/390 ratio
            self.sideDiskSize = screenWidth * 0.5
            
            // Offsets
            self.sideDiskOffsetPrevious = screenWidth * -0.15
            self.sideDiskOffsetNext = screenWidth * 0.15
            
            self.sideLabelOffsetPrevious = CGSize(width: screenWidth * -0.09, height: screenWidth * -0.10)
            self.sideLabelOffsetNext = CGSize(width: screenWidth * 0.11, height: screenWidth * -0.09)
            
            self.mainVStackOffsetY = screenWidth * 0.09
        }
    }
}
