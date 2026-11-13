import Aesthetics
import SwiftUI

@MainActor
@Observable
public final class NavigationState {
    public var selectedTab: TabItem = .home
    public var tabPaths: [TabItem: NavigationPath] = Dictionary(
        uniqueKeysWithValues: TabItem.allCases.map { ($0, NavigationPath()) }
    )

    #if os(macOS)
    /// The macOS sidebar is folded away. Here rather than in RootView because the split view
    /// re-hosts its detail column only when the tab changes, so view state there never reaches it.
    public var isSidebarCollapsed = false
    #endif

    public init() {}

    public func binding(for tab: TabItem) -> Binding<NavigationPath> {
        Binding(
            get: { self.tabPaths[tab] ?? NavigationPath() },
            set: { self.tabPaths[tab] = $0 }
        )
    }
}
