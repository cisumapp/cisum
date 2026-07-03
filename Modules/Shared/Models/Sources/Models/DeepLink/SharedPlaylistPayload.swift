import Foundation

/// The JSON body stored by the shortener (`POST /api/share`) and returned on resolve
/// (`GET /api/share/<id>`). `type` distinguishes an embedded tracklist from a provider reference.
public struct SharedPlaylistPayload: Codable, Sendable {
    public let type: String
    public let name: String?
    public let author: String?
    public let provider: String?
    public let sourceID: String?
    public let tracks: [SharedSong]?

    public init(type: String, name: String?, author: String?, provider: String?, sourceID: String?, tracks: [SharedSong]?) {
        self.type = type
        self.name = name
        self.author = author
        self.provider = provider
        self.sourceID = sourceID
        self.tracks = tracks
    }
}

public extension SharedPlaylistPayload {
    /// The server payload for a playlist to shorten. Returns nil for an already-shortened link.
    init?(_ playlist: SharedPlaylist) {
        switch playlist {
        case let .embedded(name, author, _, tracks):
            self.init(type: "embedded", name: name, author: author, provider: nil, sourceID: nil, tracks: tracks)
        case let .imported(provider, sourceID, name):
            self.init(type: "imported", name: name, author: nil, provider: provider.rawValue, sourceID: sourceID, tracks: nil)
        case .shortened:
            return nil
        }
    }

    /// Reconstructs a `SharedPlaylist` from a resolved server payload.
    func toSharedPlaylist() -> SharedPlaylist? {
        switch type {
        case "embedded":
            guard let name, let tracks, !tracks.isEmpty else { return nil }
            return .embedded(name: name, author: author, sharedBy: author, tracks: tracks)
        case "imported":
            guard let provider = provider.flatMap(MediaProvider.init(rawValue:)), let sourceID else { return nil }
            return .imported(provider: provider, sourceID: sourceID, name: name)
        default:
            return nil
        }
    }
}
