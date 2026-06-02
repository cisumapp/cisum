import Authentication
import Foundation
import Networking
import Plugins
import Profile

public final class UserDomain {
    let spotifySessionCoordinator: SpotifySessionCoordinator
    let authService: AuthService
    let supabaseService: SupabaseService
    let analyticsService: AnalyticsService

    public init(
        spotifySessionCoordinator: SpotifySessionCoordinator,
        authService: AuthService,
        supabaseService: SupabaseService,
        analyticsService: AnalyticsService
    ) {
        self.spotifySessionCoordinator = spotifySessionCoordinator
        self.authService = authService
        self.supabaseService = supabaseService
        self.analyticsService = analyticsService
    }

    public var interface: UserInterface {
        UserInterface(
            spotifySessionCoordinator: spotifySessionCoordinator,
            authService: authService,
            supabaseService: supabaseService,
            analyticsService: analyticsService
        )
    }
}
