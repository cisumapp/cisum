import Foundation
import Models

/// Concrete `SavedLibraryInterface` backing the app-wide save/add-to-playlist actions.
/// Thin @MainActor wrapper forwarding to the `PlaylistLibraryStore` actor.
@MainActor
public final class SavedLibraryService: SavedLibraryInterface {
    private let store: PlaylistLibraryStore

    public init(store: PlaylistLibraryStore) {
        self.store = store
    }

    public func isSaved(fingerprint: String) async -> Bool {
        await store.isSaved(fingerprint: fingerprint)
    }

    public func toggleSaved(_ track: SavableTrack) async -> Bool {
        await store.ensureSavedPlaylist()
        if await store.isSaved(fingerprint: track.fingerprint) {
            await store.removeItem(fingerprint: track.fingerprint, from: PlaylistLibraryStore.savedPlaylistID)
            return false
        }
        await store.appendItem(track.itemSnapshot(), to: PlaylistLibraryStore.savedPlaylistID)
        return true
    }

    public func addToPlaylist(_ track: SavableTrack, playlistID: String) async {
        await store.appendItem(track.itemSnapshot(), to: playlistID)
    }

    public func localPlaylists() async -> [LocalPlaylistRef] {
        await store.localPlaylistRefs()
    }

    @discardableResult
    public func createLocalPlaylist(title: String) async -> String {
        await store.createLocalPlaylist(title: title)
    }
}

extension SavableTrack {
    /// Maps a neutral `SavableTrack` into the store's item snapshot. `sortIndex` is a placeholder —
    /// `appendItem` assigns the real index at the end of the target playlist.
    func itemSnapshot() -> PlaylistLibraryStore.PlaylistItemSnapshot {
        PlaylistLibraryStore.PlaylistItemSnapshot(
            sortIndex: 0,
            sourceTrackID: sourceTrackID,
            sourceTrackFingerprint: fingerprint,
            title: title,
            artistName: artist,
            albumName: album,
            durationSeconds: durationSeconds,
            artworkURLString: artworkURL?.absoluteString,
            youtubeID: youtubeID,
            youtubeMusicID: youtubeMusicID,
            spotifyID: spotifyID,
            importStatus: .matched
        )
    }
}
