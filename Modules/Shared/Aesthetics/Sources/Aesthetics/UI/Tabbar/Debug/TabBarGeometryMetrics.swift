//
//  TabBarGeometryMetrics.swift
//  cisum
//

#if DEBUG
#if os(iOS)
import CoreGraphics
import Foundation

/// Which space `.global` actually resolved to for a sample.
///
/// Both real cases are legitimate: the accessory is sometimes hosted such that
/// `.global` is window space, and sometimes such that it is the accessory's own
/// space, with the platter's content origin at (0, 1.5). Samples are labelled,
/// never discarded — the `accessoryLocal` ones independently confirm the platter inset.
public enum CoordinateSpaceKind: String, Equatable, Sendable {
    case window
    case accessoryLocal
    /// Frame and screen bounds disagree — typically screen bounds lagging a rotation.
    case inconsistent
}

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
    public var horizontalSizeClassDescription: String
    public var verticalSizeClassDescription: String
    public var interfaceOrientationDescription: String
    public var coordinateSpace: CoordinateSpaceKind

    public init(
        accessoryFrame: CGRect,
        placementDescription: String,
        screenBounds: CGRect,
        safeAreaBottom: CGFloat,
        safeAreaTop: CGFloat,
        horizontalSizeClassDescription: String,
        verticalSizeClassDescription: String,
        interfaceOrientationDescription: String,
        coordinateSpace: CoordinateSpaceKind
    ) {
        self.accessoryFrame = accessoryFrame
        self.placementDescription = placementDescription
        self.screenBounds = screenBounds
        self.safeAreaBottom = safeAreaBottom
        self.safeAreaTop = safeAreaTop
        self.horizontalSizeClassDescription = horizontalSizeClassDescription
        self.verticalSizeClassDescription = verticalSizeClassDescription
        self.interfaceOrientationDescription = interfaceOrientationDescription
        self.coordinateSpace = coordinateSpace
    }

    /// `.accessoryLocal` when the frame sits at the origin of its own host;
    /// `.window` when it sits where the platter really is on screen;
    /// `.inconsistent` when the frame cannot be reconciled with `screenBounds`.
    public static func classify(frame: CGRect, screenBounds: CGRect) -> CoordinateSpaceKind {
        guard screenBounds.width > 0, screenBounds.height > 0 else {
            return .inconsistent
        }

        if frame.minY < 0 || frame.maxY > screenBounds.height + 1 {
            return .inconsistent
        }

        if frame.minX == 0, frame.minY < 8 {
            return .accessoryLocal
        }

        return .window
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

    /// Padding between our 45pt content and the system platter around it.
    ///
    /// `DynamicPlayerIsland` constrains itself to `AppConstants.dynamicPlayerIslandHeight`
    /// (45), so the probe measures our content, not the platter. On iPhone 14 the gap
    /// came out at 1.5pt via two independent derivations: `48 = 45 + 1.5 * 2` and
    /// `91 = 92.5 - 1.5`, plus `accessoryLocal` samples placing content at `minY = 1.5`.
    /// Whether this generalises across devices is exactly what this stage measures.
    public static let assumedPlatterInset: CGFloat = 1.5

    /// Compare against `accessoryHeight` (hardcoded 48).
    public var derivedPlatterHeight: CGFloat {
        measuredHeight + Self.assumedPlatterInset * 2
    }

    /// Compare against `bottomOffset` (hardcoded 91 on the iOS 26 path).
    public var derivedPlatterBottomOffset: CGFloat {
        measuredBottomOffset - Self.assumedPlatterInset
    }

    /// Paste-ready single line for comparing a run against the constants.
    public var summaryLine: String {
        String(
            format: "h%.1f w%.1f x%.1f bottom%.1f | platter h%.1f bottom%.1f | %@ | %@ | h:%@ v:%@ | %@ | safe(t%.0f b%.0f)",
            measuredHeight,
            measuredWidth,
            measuredSideInset,
            measuredBottomOffset,
            derivedPlatterHeight,
            derivedPlatterBottomOffset,
            placementDescription,
            coordinateSpace.rawValue,
            horizontalSizeClassDescription,
            verticalSizeClassDescription,
            interfaceOrientationDescription,
            safeAreaTop,
            safeAreaBottom
        )
    }
}
#endif
#endif
