import Foundation
import Models
import Observation

/// A shared playlist link awaiting user confirmation before import.
public struct PendingSharedPlaylist: Identifiable, Sendable {
    public let id: UUID
    public let playlist: SharedPlaylist

    public init(id: UUID, playlist: SharedPlaylist) {
        self.id = id
        self.playlist = playlist
    }
}

/// Holds inbound deep-link state that needs UI (currently: a playlist awaiting an import confirmation).
/// Songs auto-play and never land here; playlists do (mixed UX).
@MainActor
@Observable
public final class DeepLinkCoordinator {
    public var pendingPlaylist: PendingSharedPlaylist?

    public init() {}

    public func present(_ playlist: SharedPlaylist) {
        pendingPlaylist = PendingSharedPlaylist(id: UUID(), playlist: playlist)
    }
}
