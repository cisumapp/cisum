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
//  on-accent ≥ 7.7:1 over `accentFill`, destructive, link and warning ≥ 4.9:1.
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

    /// Needs-attention badges. The system orange is 2:1 on the cream page.
    static var textWarning: Color {
        .cisumWarning
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
    static let cisumWarning = Color.cisumAdaptive(light: "#9A4F00", dark: "#FFB45E")
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

// MARK: - Buttons

/// The page's buttons, from the tokens. `.borderedProminent` tinted with the text colour gave a
/// label in that same colour: black on black in light mode, white on white in dark.
public struct CisumButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case prominent, secondary }

    let kind: Kind

    public func makeBody(configuration: Configuration) -> some View {
        CisumButtonBody(kind: kind, configuration: configuration)
    }
}

private struct CisumButtonBody: View {
    let kind: CisumButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .padding(.horizontal, small ? 12 : 18)
            .padding(.vertical, small ? 6 : 10)
            .foregroundStyle(foreground)
            .background(kind == .prominent ? Color.textPrimary : Color.fillStrong, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        if kind == .prominent {
            return .surfaceBackground
        }
        return configuration.role == .destructive ? .textDestructive : .textPrimary
    }
}

public extension ButtonStyle where Self == CisumButtonStyle {
    /// The one call to action on a page: ink capsule, page-coloured label.
    static var cisumProminent: CisumButtonStyle {
        .init(kind: .prominent)
    }

    static var cisumSecondary: CisumButtonStyle {
        .init(kind: .secondary)
    }
}
