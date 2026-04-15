import Observation
import SwiftUI

#if os(macOS)
enum Routes: Hashable {
    case profile
    case settings
    case playlistDetail(String)
}

@Observable
final class Router {
    static let shared = Router()

    var selectedTab: TabItem = .home

    private var tabPaths: [TabItem: NavigationPath] = Dictionary(
        uniqueKeysWithValues: TabItem.allCases.map { ($0, NavigationPath()) }
    )

    func binding(for tab: TabItem) -> Binding<NavigationPath> {
        Binding(
            get: { self.tabPaths[tab] ?? NavigationPath() },
            set: { self.tabPaths[tab] = $0 }
        )
    }

    func navigate(to route: Routes) {
        updatePath(for: selectedTab) { path in
            path.append(route)
        }
    }

    func popToRoot() {
        updatePath(for: selectedTab) { path in
            path.removeLast(path.count)
        }
    }

    func pop() {
        updatePath(for: selectedTab) { path in
            guard !path.isEmpty else { return }
            path.removeLast()
        }
    }

    private func updatePath(for tab: TabItem, _ update: (inout NavigationPath) -> Void) {
        var path = tabPaths[tab] ?? NavigationPath()
        update(&path)
        tabPaths[tab] = path
    }
}

struct RouterViewModifier: ViewModifier {
    @Environment(\.router) private var router

    private func routeView(to route: Routes) -> some View {
        Group {
            switch route {
            case .profile:
                ProfileView()
            case .settings:
                SettingsView()
            case .playlistDetail(let playlistID):
                PlaylistDetailView(playlistID: playlistID)
            }
        }
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Routes.self) { newRoute in
                routeView(to: newRoute)
            }
            .enableInjection()
    }
}

extension View {
    func usingRouter() -> some View {
        modifier(RouterViewModifier())
    }
}
#endif
