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

    /// Republished by `iOSTabView` whenever the state, screen width or safe area
    /// changes. `nil` only before the first publish.
    public var accessoryOffsets: ResponsiveLayout.AccessoryOffsets?

    /// The state the offsets were resolved from. Lets the overlay branch on a
    /// meaningful value instead of reverse-engineering one from the numbers.
    public var accessoryState: ResponsiveLayout.AccessoryState?

    private init() {}
}
