//
//  NowPlayingExpandProgressPreferenceKey.swift
//  
//
//  Created by Aarav Gupta on 08/04/26.
//

import SwiftUI

struct NowPlayingExpandProgressPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension EnvironmentValues {
    @Entry var nowPlayingExpandProgress = 0.0
}
