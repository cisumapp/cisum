//
//  ViewOffsetKey.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 18/03/25.
//

import SwiftUI

struct ViewOffsetKey: PreferenceKey {
    nonisolated static let defaultValue: CGFloat = 0
    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
