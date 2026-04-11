import Observation

#if os(macOS)
enum Routes: Hashable {
    case profile
    case settings
    case playlistDetail(String)
}

@Observable
final class Router {
    static let shared = Router()

    func navigate(to route: Routes) {
        // macOS currently uses a separate navigation architecture.
    }

    func popToRoot() {
        // macOS currently uses a separate navigation architecture.
    }

    func pop() {
        // macOS currently uses a separate navigation architecture.
    }
}
#endif
