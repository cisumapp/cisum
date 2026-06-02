import Caching
import Foundation
import Library
import Models
import Player
import Playlists

public final class LibraryDomain {
    let playlistLibraryStore: PlaylistLibraryStore
    let playlistImportJobStore: PlaylistImportJobStore
    let centralMediaStore: CentralMediaStore
    let mediaCacheStore: MediaCacheStore
    let metadataCache: any VideoMetadataCaching

    public init(
        playlistLibraryStore: PlaylistLibraryStore,
        playlistImportJobStore: PlaylistImportJobStore,
        centralMediaStore: CentralMediaStore,
        mediaCacheStore: MediaCacheStore,
        metadataCache: any VideoMetadataCaching
    ) {
        self.playlistLibraryStore = playlistLibraryStore
        self.playlistImportJobStore = playlistImportJobStore
        self.centralMediaStore = centralMediaStore
        self.mediaCacheStore = mediaCacheStore
        self.metadataCache = metadataCache
    }

    public var interface: LibraryInterface {
        LibraryInterface(
            playlistLibraryStore: playlistLibraryStore,
            playlistImportJobStore: playlistImportJobStore,
            centralMediaStore: centralMediaStore,
            mediaCacheStore: mediaCacheStore,
            metadataCache: metadataCache
        )
    }
}
