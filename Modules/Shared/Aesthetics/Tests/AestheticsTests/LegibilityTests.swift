#if os(iOS)
import Testing
import SwiftUI
import UIKit
@testable import Aesthetics

@Test func secondaryTextFlipsDarkOnWhiteBackground() {
    // White surface → light-gray cisumSecondaryText fails W3C → must flip to a dark color.
    let flipped = Color.cisumSecondaryText.safeTextColor(over: .white)
    #expect(UIColor(flipped).perceivedBrightness < 125)
}

@Test func primaryTextStaysReadableOnBlackBackground() {
    let flipped = Color.cisumPrimaryText.safeTextColor(over: .black)
    #expect(UIColor(flipped).perceivedBrightness > 125)
}
#endif
