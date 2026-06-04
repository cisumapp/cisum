//
//  EnvironmentValues+Config.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 09/05/25.
//

#if os(iOS) || os(macOS)

import SwiftUI

public extension EnvironmentValues {
    var sliderConfig: SliderConfig {
        get { self[SliderConfigEnvironmentKey.self] }
        set { self[SliderConfigEnvironmentKey.self] = newValue
        }
    }
}

extension EnvironmentValues {
    var navigationBarStyle: NavigationBarStyle {
        get { self[NavigationBarStyleKey.self] }
        set { self[NavigationBarStyleKey.self] = newValue }
    }
}

#endif
