import SwiftUI

@MainActor
public enum AppRoute: Hashable {
    case home
    case profile
    case settings
    case plugins
    case search
    case library
    case recents
    case playlist(id: String)
    case artist(id: String)
    case album(id: String)
    /// One of the Library's own pages, e.g. from the macOS sidebar.
    case librarySongs
    case libraryAlbums
    case libraryArtists
    case libraryPlaylists
    /// An album or artist built from the user's own songs, not the catalog's.
    case libraryAlbum(id: String)
    case libraryArtist(id: String)
    case equalizer
    case login
    case spotifyLogin
    case youtubeLogin
}

@MainActor
public protocol Router: AnyObject {
    func navigate(to route: AppRoute)
    func pop()
    /// Clears the selected tab's stack back to its root.
    func popToRoot()
}

@MainActor
public final class EmptyRouter: Router {
    public init() {}
    public func navigate(to _: AppRoute) {}
    public func pop() {}
    public func popToRoot() {}
}

private struct RouterKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: Router = EmptyRouter()
}

public extension EnvironmentValues {
    var router: Router {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}

public extension View {
    @MainActor
    func usingRouter(_ router: Router = EmptyRouter()) -> some View {
        environment(\.router, router)
    }
}
