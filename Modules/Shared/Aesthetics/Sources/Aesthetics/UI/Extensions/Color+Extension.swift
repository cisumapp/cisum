//
//  Color+Extension.swift
//  cisum
//
//  Created by Aarav Gupta on 25/12/25.
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public extension Color {
    @MainActor static var dynamicAccent: Color = .cisumAccent

    @MainActor
    static func updateDynamicAccent(_ color: Color?) {
        dynamicAccent = color ?? .cisumAccent
    }

    @MainActor
    static func resetDynamicAccent() {
        dynamicAccent = .cisumAccent
    }

    static let cisumPrimary = Color.cisumAdaptive(light: "#FFFFFF", dark: "#000000")
    static let cisumBg = Color.cisumAdaptive(light: "#FDF6E3", dark: "#101014")
    static let cisumSurface = Color.cisumAdaptive(light: "#EEE8D5", dark: "#1C1C22")
    static let cisumElevatedSurface = Color.cisumAdaptive(light: "#FFF9EA", dark: "#272731")
    static let cisumAccent = Color.cisumAdaptive(light: "#CBC2A5", dark: "#B8A879")
    static let cisumYellow = Color.cisumAdaptive(light: "#B58900", dark: "#E6B84B")
    static let cisumDark = Color.cisumAdaptive(light: "#2B221B", dark: "#F2EBDC")
    static let cisumPrimaryText = Color.cisumAdaptive(light: "#151515", dark: "#F7F4EC")
    static let cisumSecondaryText = Color.cisumAdaptive(light: "#68635B", dark: "#B7B1A6")
    
    static var cisumChromeSubtle: Color {
        .white.opacity(0.1)
    }

    static var cisumChromeBorder: Color {
        .white.opacity(0.2)
    }

    static var cisumChromeStrong: Color {
        .white.opacity(0.32)
    }

    static var cisumTrackActive: Color {
        .white.opacity(0.9)
    }

    static var cisumTrackInactive: Color {
        .white.opacity(0.22)
    }

    static var cisumTrackSecondary: Color {
        .white.opacity(0.5)
    }

    #if os(iOS)
    var uiColor: UIColor {
        UIColor(self)
    }

    #elseif os(macOS)
    var uiColor: NSColor {
        NSColor(self)
    }
    #endif

    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double((rgb >> 0) & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    private static func cisumAdaptive(light: String, dark: String) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif os(macOS)
        Color(NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(Color(hex: bestMatch == .darkAqua ? dark : light))
        })
        #else
        Color(hex: light)
        #endif
    }
}
