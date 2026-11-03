//
//  Legibility.swift
//  Aesthetics
//
//  Surface-aware text legibility. A screen declares its effective background once via
//  `.legibilityBackground(_:)`; text uses `.legibleForeground(_:)`, which picks the ink
//  purely from the *background's actual luminance* — light background → dark ink, dark
//  background → light ink. This is deliberately independent of the system light/dark mode:
//  a light playlist on a dark-mode device still gets dark text, and vice versa.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

public enum LegibilityRole: Sendable { case primary, secondary, accent }

public extension EnvironmentValues {
    @Entry var legibilityBackground: Color = .cisumBg
    /// The artwork's own text colours, when a screen is painted in its palette. `nil` falls
    /// back to the brand inks.
    @Entry var legibilityPalette: ImageColorPalette?
}

// Non-adaptive brand inks. Chosen by background luminance, NOT by system appearance.
private let cisumDarkInk = Color(hex: "#151515")
private let cisumLightInk = Color(hex: "#F7F4EC")

private struct LegibleForeground: ViewModifier {
    let role: LegibilityRole
    @Environment(\.legibilityBackground) private var background
    @Environment(\.legibilityPalette) private var palette

    func body(content: Content) -> some View {
        content.foregroundStyle(resolved)
    }

    private var resolved: Color {
        // The palette's title and song colours, each kept only if it reads on this background.
        if let palette {
            switch role {
            case .primary: return palette.title.safeTextColor(over: background)
            case .secondary: return palette.songs.safeTextColor(over: background).opacity(0.8)
            case .accent: return palette.dominant.safeTextColor(over: background)
            }
        }
        // perceivedBrightness is 0–255; W3C legibility threshold is 125. On macOS too: the
        // semantic colours follow the system appearance, not the surface under the text.
        let backgroundIsLight = PlatformColor(background).perceivedBrightness > 125
        let ink = backgroundIsLight ? cisumDarkInk : cisumLightInk
        switch role {
        case .primary: return ink
        case .secondary: return ink.opacity(0.7)
        case .accent: return Color.dynamicAccent.safeTextColor(over: background)
        }
    }
}

public extension View {
    func legibilityBackground(_ color: Color) -> some View {
        environment(\.legibilityBackground, color)
    }

    func legibleForeground(_ role: LegibilityRole = .primary) -> some View {
        modifier(LegibleForeground(role: role))
    }
}
