import Foundation

public struct PersistedTrackState: Codable, Sendable {
    public let mediaID: String
    public let title: String
    public let artist: String
    public let albumName: String?
    public let artworkURL: URL?
    public let isExplicit: Bool
    public let playbackTime: TimeInterval

    public init(
        mediaID: String,
        title: String,
        artist: String,
        albumName: String?,
        artworkURL: URL?,
        isExplicit: Bool,
        playbackTime: TimeInterval
    ) {
        self.mediaID = mediaID
        self.title = title
        self.artist = artist
        self.albumName = albumName
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
        self.playbackTime = playbackTime
    }
}
