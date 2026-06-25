//
//  Legibility.swift
//  Aesthetics
//
//  Surface-aware text legibility. A screen declares its effective background once via
//  `.legibilityBackground(_:)`; text uses `.legibleForeground(_:)`, which flips the base
//  color to a readable shade against that surface using the W3C helpers in
//  ImageColorExtractor (`Color.safeTextColor(over:)`).
//

import SwiftUI

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

private struct LegibleForeground: ViewModifier {
    let role: LegibilityRole
    @Environment(\.legibilityBackground) private var background

    func body(content: Content) -> some View {
        let base: Color = switch role {
        case .primary: .cisumPrimaryText
        case .secondary: .cisumSecondaryText
        case .accent: .dynamicAccent
        }
        #if os(iOS)
        return content.foregroundStyle(base.safeTextColor(over: background))
        #else
        return content.foregroundStyle(base) // ponytail: contrast helpers are iOS-only; macOS keeps base
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
