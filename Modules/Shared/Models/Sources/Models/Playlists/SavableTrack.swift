import Foundation
import Utilities

/// A provider-neutral description of a song the user wants to save or add to a playlist.
/// Feature modules build this from their own track types (YouTubeMusicSong, the player's
/// current song, a search row) and hand it to `SavedLibraryInterface`.
public struct SavableTrack: Sendable, Equatable, Identifiable {
    public var id: String {
        fingerprint
    }

    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let durationSeconds: Double?
    public let isExplicit: Bool
    public let sourceTrackID: String?
    public let youtubeID: String?
    public let youtubeMusicID: String?
    public let spotifyID: String?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        durationSeconds: Double? = nil,
        isExplicit: Bool = false,
        sourceTrackID: String? = nil,
        youtubeID: String? = nil,
        youtubeMusicID: String? = nil,
        spotifyID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationSeconds = durationSeconds
        self.isExplicit = isExplicit
        self.sourceTrackID = sourceTrackID
        self.youtubeID = youtubeID
        self.youtubeMusicID = youtubeMusicID
        self.spotifyID = spotifyID
    }

    /// Stable identity used to dedupe within a playlist and to answer "is this saved?".
    /// Uses the same normalization the app uses for ranking so the same song from different
    /// providers collapses to one fingerprint.
    public var fingerprint: String {
        let normalized = normalizedRankingText("\(title) \(artist)")
        return normalized.isEmpty ? title.lowercased() : normalized
    }
}
