import Foundation
import Observation

@Observable
@MainActor
public final class ServicesContainer {
    public let coreServices: CoreServices
    public let playbackServices: PlaybackServices
    public let searchServices: SearchServices
    public let libraryServices: LibraryServices
    public let userServices: UserServices
    public let providerServices: ProviderServices
    public let appServices: AppServices

    public init(
        coreServices: CoreServices,
        playbackServices: PlaybackServices,
        searchServices: SearchServices,
        libraryServices: LibraryServices,
        userServices: UserServices,
        providerServices: ProviderServices,
        appServices: AppServices
    ) {
        self.coreServices = coreServices
        self.playbackServices = playbackServices
        self.searchServices = searchServices
        self.libraryServices = libraryServices
        self.userServices = userServices
        self.providerServices = providerServices
        self.appServices = appServices
    }
}
