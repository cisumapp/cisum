import Caching
import Foundation
import Networking
import Plugins

public final class CoreDomain {
    public let streamingProviderSettings: StreamingProviderSettings
    public let prefetchSettings: PrefetchSettings
    public let networkMonitor: NetworkPathMonitor

    public init(
        streamingProviderSettings: StreamingProviderSettings,
        prefetchSettings: PrefetchSettings,
        networkMonitor: NetworkPathMonitor
    ) {
        self.streamingProviderSettings = streamingProviderSettings
        self.prefetchSettings = prefetchSettings
        self.networkMonitor = networkMonitor
    }
}

public extension CoreDomain {
    var interface: CoreInterface {
        CoreInterface(
            streamingProviderSettings: streamingProviderSettings,
            prefetchSettings: prefetchSettings,
            networkMonitor: networkMonitor
        )
    }
}
