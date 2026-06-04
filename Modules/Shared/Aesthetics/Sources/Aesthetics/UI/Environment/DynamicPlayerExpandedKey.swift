//
//  DynamicPlayerExpandedKey.swift
//
//
//  Created by Aarav Gupta on 15/04/26.
//

import SwiftUI

public extension EnvironmentValues {
    @Entry var isDynamicPlayerExpanded: Binding<Bool> = .constant(false)
}
