//
//  DesignTokens.swift
//  Aesthetics
//
//  The colours every cisum screen draws with, by role. A view names the role (`.textSecondary`,
//  `.fillSubtle`) and never a value, so light mode, dark mode and the brand palette stay one
//  decision made here.
//
//  Contrast, WCAG 2.1, checked for both modes against `surfaceBackground` and `surfaceRaised`:
//  text primary ≥ 14:1, secondary ≥ 4.8:1, tertiary ≥ 3.6:1 (captions and hints only),
//  on-accent ≥ 7.7:1 over `accentFill`, destructive and link ≥ 5:1.
//
//  Text over artwork or the player's dimmed backdrop is always on a dark surface, whatever the
//  system appearance: it uses the `onMedia` tokens, or `legibleForeground`, which picks its ink
//  from the surface it sits on.
//

import SwiftUI

public extension ShapeStyle where Self == Color {
    // MARK: Surfaces

    /// The page.
    static var surfaceBackground: Color {
        .cisumBg
    }

    /// Grouped rows, fields and cards on the page.
    static var surfaceRaised: Color {
        .cisumSurface
    }

    /// Menus and popovers above raised content.
    static var surfaceElevated: Color {
        .cisumElevatedSurface
    }

    // MARK: Text

    static var textPrimary: Color {
        .cisumPrimaryText
    }

    static var textSecondary: Color {
        .cisumSecondaryText
    }

    /// Captions, placeholders and hints: never body text.
    static var textTertiary: Color {
        .cisumTertiaryText
    }

    /// Text and icons on `accentFill`. Dark in both modes: light text on the accent is 2:1.
    static var textOnAccent: Color {
        .cisumInk
    }

    static var textDestructive: Color {
        .cisumDestructive
    }

    static var textLink: Color {
        .cisumLink
    }

    // MARK: Fills and lines

    /// Placeholders, pressed rows, skeletons.
    static var fillSubtle: Color {
        .cisumFillSubtle
    }

    /// Secondary buttons, chips, the unselected segment.
    static var fillStrong: Color {
        .cisumFillStrong
    }

    static var separatorLine: Color {
        .cisumSeparator
    }

    /// The brand call to action. Pair with `textOnAccent`.
    static var accentFill: Color {
        .cisumAccent
    }

    // MARK: On media (artwork, the player)

    static var onMedia: Color {
        .white
    }

    static var onMediaSecondary: Color {
        .white.opacity(0.72)
    }
}

extension Color {
    static let cisumTertiaryText = Color.cisumAdaptive(light: "#7D776D", dark: "#8F897F")
    static let cisumInk = Color(hex: "#151515")
    /// The brand yellow, darkened in light mode: `cisumYellow` there is 2.8:1 on the page.
    static let cisumLink = Color.cisumAdaptive(light: "#7A5C00", dark: "#E6B84B")
    static let cisumDestructive = Color.cisumAdaptive(light: "#B3261E", dark: "#FF7A70")
    static let cisumFillSubtle = Color.cisumAdaptive(light: "#000000", dark: "#FFFFFF", opacity: 0.06)
    static let cisumFillStrong = Color.cisumAdaptive(light: "#000000", dark: "#FFFFFF", opacity: 0.12)
    static let cisumSeparator = Color.cisumAdaptive(light: "#000000", dark: "#FFFFFF", opacity: 0.1)
}

public extension View {
    /// Makes the tokens the default text styles below this view: `.primary`, `.secondary` and
    /// `.tertiary` (and plain `Text`) resolve to `textPrimary`, `textSecondary` and `textTertiary`
    /// instead of the system's neutral greys, which sat cold next to the warm brand surfaces.
    func cisumTextStyles() -> some View {
        foregroundStyle(.textPrimary, .textSecondary, .textTertiary)
    }
}
