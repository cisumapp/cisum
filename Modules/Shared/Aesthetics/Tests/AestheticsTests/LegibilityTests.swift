#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import Aesthetics

// The modifier decides ink purely from background luminance (threshold 125), independent
// of system appearance. These assert the two halves of that decision.

@Test func lightBackgroundIsAboveThresholdAndDarkInkIsDark() {
    #expect(UIColor(Color.white).perceivedBrightness > 125)            // white bg ⇒ "light"
    #expect(UIColor(Color(hex: "#151515")).perceivedBrightness < 125)  // ⇒ dark ink, readable on light
}

@Test func darkBackgroundIsBelowThresholdAndLightInkIsLight() {
    #expect(UIColor(Color.black).perceivedBrightness < 125)            // black bg ⇒ "dark"
    #expect(UIColor(Color(hex: "#F7F4EC")).perceivedBrightness > 125)  // ⇒ light ink, readable on dark
}

@Test func accentFallsBackWhenIllegibleOverBackground() {
    // safeTextColor (used for the .accent role) flips to a contrasting shade when the
    // accent itself can't be read over the surface.
    let onWhite = Color.white.safeTextColor(over: .white)
    #expect(UIColor(onWhite).perceivedBrightness < 125)
}
#endif
