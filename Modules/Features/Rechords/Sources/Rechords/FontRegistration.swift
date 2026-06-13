//
//  FontRegistration.swift
//  Rechords
//
//  Created by Aarav Gupta on 13/05/26.
//

import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit

typealias PlatformUIFont = UIFont
#elseif os(macOS)
import AppKit

typealias PlatformUIFont = NSFont
#endif

public enum FontRegistration {
    private nonisolated(unsafe) static var registered = false

    public static func registerFonts() {
        guard !registered else { return }
        registered = true

        guard let fontURL = Bundle.module.url(forResource: "NotoSerif-Italic", withExtension: "ttf") else {
            PerfLog.debug(" Font file not found in bundle")
            return
        }

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            PerfLog.debug(" Font registration failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
        }
    }

    public static func printRegisteredFontName() {
        #if canImport(UIKit)
        for family in PlatformUIFont.familyNames.sorted() {
            let names = PlatformUIFont.fontNames(forFamilyName: family)
            if names.contains(where: { $0.lowercased().contains("noto") }) {
                PerfLog.debug("Family: \(family)")
                names.forEach { PerfLog.debug("  → \($0)") }
            }
        }
        #endif
    }

    public static func testVariableAxes() {
        #if canImport(UIKit)
        guard let font = PlatformUIFont(name: "NotoSerif-Italic", size: 16) else { return }
        #else
        guard let font = PlatformUIFont(name: "NotoSerif-Italic", size: 16) else { return }
        #endif

        if let axes = CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]] {
            for axis in axes {
                PerfLog.debug("Axis: \(axis[kCTFontVariationAxisNameKey as String] ?? "")")
                PerfLog.debug("  ID:  \(axis[kCTFontVariationAxisIdentifierKey as String] ?? "")")
                PerfLog.debug("  Min: \(axis[kCTFontVariationAxisMinimumValueKey as String] ?? "")")
                PerfLog.debug("  Max: \(axis[kCTFontVariationAxisMaximumValueKey as String] ?? "")")
            }
        } else {
            PerfLog.debug("No variation axes found")
        }
    }
}
