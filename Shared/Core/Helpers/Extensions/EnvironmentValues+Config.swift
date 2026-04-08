//
//  EnvironmentValues+Config.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 09/05/25.
//

#if os(iOS)

import SwiftUI

extension EnvironmentValues {
    var sliderConfig: SliderConfig {
        get { self[SliderConfigEnvironmentKey.self] }
        set { self[SliderConfigEnvironmentKey.self] = newValue
        }
    }
}
#endif
