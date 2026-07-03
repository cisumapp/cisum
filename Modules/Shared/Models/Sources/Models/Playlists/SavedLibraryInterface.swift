import Foundation

/// A lightweight reference to a user-made local playlist, for pickers that can't depend on the
/// Playlists module (e.g. an "Add to Playlist" sheet in the Player).
public struct LocalPlaylistRef: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Save / add-to-playlist actions exposed to feature modules that cannot depend on the
/// Playlists module directly (e.g. the Player's now-playing star). Concrete impl lives in
/// the Playlists module and is injected via `\.savedLibrary` at the composition root.
@MainActor
public protocol SavedLibraryInterface: AnyObject {
    /// Whether a track with this fingerprint is in the cisum "Saved" collection.
    func isSaved(fingerprint: String) async -> Bool
    /// Adds/removes the track from "Saved". Returns the new saved state.
    func toggleSaved(_ track: SavableTrack) async -> Bool
    /// Appends the track to an arbitrary playlist (deduped by fingerprint).
    func addToPlaylist(_ track: SavableTrack, playlistID: String) async
    /// The user's local (cisum-made) playlists, most-recent first.
    func localPlaylists() async -> [LocalPlaylistRef]
    /// Creates an empty local playlist and returns its ID.
    @discardableResult
    func createLocalPlaylist(title: String) async -> String
}
