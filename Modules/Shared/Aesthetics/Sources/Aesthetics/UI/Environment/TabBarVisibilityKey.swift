//
//  TabBarVisibilityKey.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import SwiftUI

public extension EnvironmentValues {
    @Entry var tabBarVisibility: Visibility = .visible

    @Entry var tabBarBottomAccessory: AnyView?
}
