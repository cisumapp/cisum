import Foundation
import SwiftData

public enum PlaylistItemImportStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case matched
    case uncertain
    case failed
    case skipped
}

@Model
public final class PlaylistItem {
    @Attribute(.unique) public var itemKey: String

    public var playlistID: String
    public var sortIndex: Int

    public var sourceTrackID: String?
    public var sourceTrackFingerprint: String

    public var title: String
    public var artistName: String?
    public var albumName: String?
    public var isrc: String?
    public var durationSeconds: Double?
    public var artworkURLString: String?

    public var youtubeID: String?
    public var youtubeMusicID: String?
    public var spotifyID: String?
    public var tidalID: String?
    public var qobuzID: String?
    public var soundcloudID: String?
    public var deezerID: String?
    public var appleMusicID: String?
    /// Whether the source marked the track explicit. `nil` for items saved before this was kept;
    /// optional so the store migrates lightly (see `CisumMigrationPlan`).
    public var isExplicit: Bool?

    public var resolutionConfidence: Double?

    /// Canonical Song.songID this item reconciled into. Nil until the importer resolves it.
    public var canonicalSongID: String?

    public var importStatusRawValue: String
    public var importErrorCode: String?
    public var importErrorMessage: String?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify)
    public var playlist: Playlist?

    public init(
        playlistID: String,
        sortIndex: Int,
        sourceTrackID: String? = nil,
        sourceTrackFingerprint: String,
        title: String,
        artistName: String? = nil,
        albumName: String? = nil,
        isrc: String? = nil,
        durationSeconds: Double? = nil,
        artworkURLString: String? = nil,
        youtubeID: String? = nil,
        youtubeMusicID: String? = nil,
        spotifyID: String? = nil,
        tidalID: String? = nil,
        qobuzID: String? = nil,
        soundcloudID: String? = nil,
        deezerID: String? = nil,
        appleMusicID: String? = nil,
        isExplicit: Bool? = nil,
        resolutionConfidence: Double? = nil,
        canonicalSongID: String? = nil,
        importStatus: PlaylistItemImportStatus = .pending,
        importErrorCode: String? = nil,
        importErrorMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemKey = Self.makeItemKey(playlistID: playlistID, sortIndex: sortIndex)
        self.playlistID = playlistID
        self.sortIndex = sortIndex
        self.sourceTrackID = sourceTrackID
        self.sourceTrackFingerprint = sourceTrackFingerprint
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.isrc = isrc
        self.durationSeconds = durationSeconds
        self.artworkURLString = artworkURLString
        self.youtubeID = youtubeID
        self.youtubeMusicID = youtubeMusicID
        self.spotifyID = spotifyID
        self.tidalID = tidalID
        self.qobuzID = qobuzID
        self.soundcloudID = soundcloudID
        self.deezerID = deezerID
        self.appleMusicID = appleMusicID
        self.isExplicit = isExplicit
        self.resolutionConfidence = resolutionConfidence
        self.canonicalSongID = canonicalSongID
        self.importStatusRawValue = importStatus.rawValue
        self.importErrorCode = importErrorCode
        self.importErrorMessage = importErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var importStatus: PlaylistItemImportStatus {
        get { PlaylistItemImportStatus(rawValue: importStatusRawValue) ?? .pending }
        set { importStatusRawValue = newValue.rawValue }
    }

    public static func makeItemKey(playlistID: String, sortIndex: Int) -> String {
        "\(playlistID)::\(sortIndex)"
    }
}

public extension PlaylistItem {
    /// An unsaved item for a track fetched from a provider, so a playlist or album that is not
    /// in the library lists and plays its tracks like a saved one. Nothing is persisted unless it
    /// is inserted.
    convenience init(remote track: IncomingTrack, playlistID: String, sortIndex: Int) {
        self.init(
            playlistID: playlistID,
            sortIndex: sortIndex,
            sourceTrackID: track.providerTrackID,
            sourceTrackFingerprint: "\(track.provider.rawValue):\(track.providerTrackID)",
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumName,
            isrc: track.isrc,
            durationSeconds: track.durationSeconds,
            artworkURLString: track.artworkURLString,
            youtubeID: track.provider == .youtube ? track.providerTrackID : nil,
            youtubeMusicID: track.provider == .youtubeMusic ? track.providerTrackID : nil,
            spotifyID: track.provider == .spotify ? track.providerTrackID : nil,
            appleMusicID: track.provider == .appleMusic ? track.providerTrackID : nil,
            isExplicit: track.isExplicit
        )
    }
}
