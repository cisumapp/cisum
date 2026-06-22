//
//  TabBarStateStore.swift
//  cisum
//

import SwiftUI

/// Process-scoped observable store that bridges the tab-bar accessory layout
/// from the main SwiftUI tree into any detached UIWindow (e.g. universalOverlay).
///
/// `@MainActor` ensures all reads and writes happen on the main thread,
/// which is where SwiftUI body evaluations and UIKit layout callbacks run.
@MainActor
@Observable
public final class TabBarStateStore {
    public static let shared = TabBarStateStore()

    /// Set by `iOSTabView.bottomTabBar` each time phase or geometry changes.
    /// `nil` only before the first layout pass.
    public var accessoryOffsets: ResponsiveLayout.AccessoryOffsets?

    private init() {}
}
