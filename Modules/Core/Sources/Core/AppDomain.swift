import Aesthetics
import Foundation
import Player
import Search
import SwiftData
import Utilities
import YouTubeSDK

public final class AppDomain {
    let youtube: YouTube
    let router: Router
    let modelContainer: ModelContainer
    let playerPresentationController: PlayerPresentationController
    let searchOverlayController: SearchOverlayController

    public init(
        youtube: YouTube,
        router: Router,
        modelContainer: ModelContainer,
        playerPresentationController: PlayerPresentationController,
        searchOverlayController: SearchOverlayController
    ) {
        self.youtube = youtube
        self.router = router
        self.modelContainer = modelContainer
        self.playerPresentationController = playerPresentationController
        self.searchOverlayController = searchOverlayController
    }

    public var interface: AppInterface {
        AppInterface(
            youtube: youtube,
            router: router,
            modelContainer: modelContainer,
            playerPresentationController: playerPresentationController,
            searchOverlayController: searchOverlayController
        )
    }
}
