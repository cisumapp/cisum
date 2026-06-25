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

private struct LegibilityBackgroundKey: EnvironmentKey {
    static let defaultValue: Color = .cisumBg
}

public extension EnvironmentValues {
    var legibilityBackground: Color {
        get { self[LegibilityBackgroundKey.self] }
        set { self[LegibilityBackgroundKey.self] = newValue }
    }
}

// Non-adaptive brand inks. Chosen by background luminance, NOT by system appearance.
private let cisumDarkInk = Color(hex: "#151515")
private let cisumLightInk = Color(hex: "#F7F4EC")

private struct LegibleForeground: ViewModifier {
    let role: LegibilityRole
    @Environment(\.legibilityBackground) private var background

    func body(content: Content) -> some View {
        content.foregroundStyle(resolved)
    }

    private var resolved: Color {
        #if os(iOS)
        // perceivedBrightness is 0–255; W3C legibility threshold is 125.
        let backgroundIsLight = UIColor(background).perceivedBrightness > 125
        let ink = backgroundIsLight ? cisumDarkInk : cisumLightInk
        switch role {
        case .primary: return ink
        case .secondary: return ink.opacity(0.7)
        case .accent: return Color.dynamicAccent.safeTextColor(over: background)
        }
        #else
        switch role {
        case .primary: return .cisumPrimaryText
        case .secondary: return .cisumSecondaryText
        case .accent: return .dynamicAccent
        }
        #endif
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
