import SwiftUI

public enum TabItem: String, CaseIterable {
    case home, discover, library, search

    public var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

public extension TabItem {
    /// Sidebar / tab-bar label. Single source of truth so the macOS sidebar and the
    /// iOS tab bar can never drift apart.
    var title: String {
        switch self {
        case .home: "Home"
        case .discover: "Discover"
        case .library: "Library"
        case .search: "Search"
        }
    }

    /// SF Symbol for the tab.
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .discover: "globe"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }
}

public enum ScrollPhases: Equatable {
    case idle
    case interacting
    case decelerating

    @available(iOS 18.0, macOS 15.0, *)
    public init(_ nativePhase: ScrollPhase) {
        switch nativePhase {
        case .idle:
            self = .idle
        case .interacting:
            self = .interacting
        case .decelerating:
            self = .decelerating
        case .tracking:
            self = .idle
        case .animating:
            self = .idle
        }
    }
}
