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

    /// The computed offsets describing where the tab bar accessory (mini-player) should sit.
    /// Set by `iOSTabView` and read by `playerContent` inside the universalOverlay window.
    @Entry var tabBarAccessoryOffsets: ResponsiveLayout.AccessoryOffsets? = nil
}
