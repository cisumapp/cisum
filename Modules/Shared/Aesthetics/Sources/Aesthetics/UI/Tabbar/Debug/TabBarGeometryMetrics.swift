//
//  TabBarGeometryMetrics.swift
//  cisum
//

#if DEBUG
#if os(iOS)
import CoreGraphics
import Foundation

/// One sample of the native `.tabViewBottomAccessory`'s real geometry.
///
/// Derived properties are named to line up 1:1 with the hardcoded constants in
/// `ResponsiveLayout.AccessoryOffsets`, so a sample can be compared against them directly.
public struct TabAccessoryMetrics: Equatable, Sendable {
    public var accessoryFrame: CGRect
    public var placementDescription: String
    public var screenBounds: CGRect
    public var safeAreaBottom: CGFloat
    public var safeAreaTop: CGFloat
    public var isLandscape: Bool

    public init(
        accessoryFrame: CGRect,
        placementDescription: String,
        screenBounds: CGRect,
        safeAreaBottom: CGFloat,
        safeAreaTop: CGFloat,
        isLandscape: Bool
    ) {
        self.accessoryFrame = accessoryFrame
        self.placementDescription = placementDescription
        self.screenBounds = screenBounds
        self.safeAreaBottom = safeAreaBottom
        self.safeAreaTop = safeAreaTop
        self.isLandscape = isLandscape
    }

    /// Compare against `ResponsiveLayout` `accessoryHeight` (hardcoded 48).
    public var measuredHeight: CGFloat {
        accessoryFrame.height
    }

    /// Compare against `width` (hardcoded `screenWidth - 42`).
    public var measuredWidth: CGFloat {
        accessoryFrame.width
    }

    /// Compare against `sideInset` (hardcoded 21).
    public var measuredSideInset: CGFloat {
        accessoryFrame.minX
    }

    /// Distance from the screen's bottom edge to the accessory's bottom edge.
    /// Compare against `bottomOffset` (hardcoded 91 on the iOS 26 path).
    public var measuredBottomOffset: CGFloat {
        screenBounds.maxY - accessoryFrame.maxY
    }

    /// `.global` in SwiftUI is the root of the *hosting* hierarchy, which is not
    /// guaranteed to be the window. If the accessory is hosted in its own controller
    /// the origin reads near zero and every derived value above is meaningless.
    /// The HUD surfaces this as a red warning — check it before trusting any number.
    public var looksLikeWindowCoordinates: Bool {
        accessoryFrame.minY > screenBounds.height * 0.5 && accessoryFrame.minX > 0
    }

    /// Paste-ready single line for comparing a run against the constants.
    public var summaryLine: String {
        String(
            format: "h%.1f w%.1f x%.1f bottom%.1f | %@ | safe(t%.0f b%.0f) | %@",
            measuredHeight,
            measuredWidth,
            measuredSideInset,
            measuredBottomOffset,
            placementDescription,
            safeAreaTop,
            safeAreaBottom,
            isLandscape ? "landscape" : "portrait"
        )
    }
}
#endif
#endif
