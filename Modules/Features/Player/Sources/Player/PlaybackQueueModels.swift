import AVFoundation
import Foundation
import Models
import Radio
import YouTubeSDK

public struct QueueCandidateSnapshot: Sendable, Hashable, Codable {
    public let streamKind: String
    public let mimeType: String?
    public let itag: Int?
    public let expiresAt: Date?
    public let isCompatible: Bool
    public let providerID: String?

    public init(streamKind: String, mimeType: String?, itag: Int?, expiresAt: Date?, isCompatible: Bool, providerID: String?) {
        self.streamKind = streamKind
        self.mimeType = mimeType
        self.itag = itag
        self.expiresAt = expiresAt
        self.isCompatible = isCompatible
        self.providerID = providerID
    }

    public init(_ candidate: PlaybackCandidate) {
        self.init(
            streamKind: candidate.streamKind.rawValue,
            mimeType: candidate.mimeType,
            itag: candidate.itag,
            expiresAt: candidate.expiresAt,
            isCompatible: candidate.isCompatible,
            providerID: candidate.providerID
        )
    }
}

public struct QueueIdentitySnapshot: Sendable, Hashable, Codable {
    public let canonicalID: String
    public let activeRepresentationKey: String?
    public let hydrationState: [String]
    public let candidateSnapshot: [QueueCandidateSnapshot]

    public init(
        canonicalID: String,
        activeRepresentationKey: String? = nil,
        hydrationState: [String] = [],
        candidateSnapshot: [QueueCandidateSnapshot] = []
    ) {
        self.canonicalID = canonicalID
        self.activeRepresentationKey = activeRepresentationKey
        self.hydrationState = hydrationState
        self.candidateSnapshot = candidateSnapshot
    }
}

public struct CachedRadioTrack: Identifiable, Sendable, Equatable {
    public var id: String {
        videoID
    }

    public let videoID: String
    public let title: String
    public let artist: String
    public let albumName: String?
    public let thumbnailURL: URL?
    public let isExplicit: Bool

    public var fingerprint: String {
        "\(title.lowercased())|\(artist.lowercased())"
    }

    public init(
        videoID: String,
        title: String,
        artist: String,
        albumName: String?,
        thumbnailURL: URL?,
        isExplicit: Bool
    ) {
        self.videoID = videoID
        self.title = title
        self.artist = artist
        self.albumName = albumName
        self.thumbnailURL = thumbnailURL
        self.isExplicit = isExplicit
    }

    public init(song: YouTubeMusicSong) {
        self.videoID = song.videoId
        self.title = song.title
        self.artist = song.artistsDisplay
        self.albumName = song.album
        self.thumbnailURL = song.thumbnailURL
        self.isExplicit = song.isExplicit
    }

    @MainActor
    public init(cached: RadioSessionStore.CachedTrack) {
        self.videoID = cached.videoID
        self.title = cached.title
        self.artist = cached.artist
        self.albumName = cached.albumName
        self.thumbnailURL = cached.thumbnailURL
        self.isExplicit = cached.isExplicit
    }

    @MainActor
    public var persisted: RadioSessionStore.CachedTrack {
        RadioSessionStore.CachedTrack(
            videoID: videoID,
            title: title,
            artist: artist,
            albumName: albumName,
            thumbnailURLString: thumbnailURL?.absoluteString,
            isExplicit: isExplicit
        )
    }

    public var queueIdentity: QueueIdentitySnapshot {
        QueueIdentitySnapshot(
            canonicalID: canonicalQueueID(for: fingerprint, fallback: videoID),
            activeRepresentationKey: nil,
            hydrationState: ["metadataResolved"],
            candidateSnapshot: []
        )
    }
}

public enum PlaybackQueueEntry: Equatable, Sendable {
    case song(YouTubeMusicSong)
    case video(YouTubeVideo)
    case cachedRadio(CachedRadioTrack)
    case external(ExternalQueueTrack)

    public static func == (lhs: PlaybackQueueEntry, rhs: PlaybackQueueEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.song(l), .song(r)): l.id == r.id
        case let (.video(l), .video(r)): l.id == r.id
        case let (.cachedRadio(l), .cachedRadio(r)): l.id == r.id
        case let (.external(l), .external(r)): l == r
        default: false
        }
    }

    public var mediaID: String {
        switch self {
        case let .song(song):
            song.videoId
        case let .video(video):
            video.id
        case let .cachedRadio(track):
            track.videoID
        case let .external(track):
            track.mediaID
        }
    }

    public var fingerprint: String {
        switch self {
        case let .song(song):
            "\(song.title.lowercased())|\(song.artistsDisplay.lowercased())"
        case let .video(video):
            "\(video.title.lowercased())|\(video.author.lowercased())"
        case let .cachedRadio(track):
            track.fingerprint
        case let .external(track):
            "\(track.title.lowercased())|\(track.artist.lowercased())"
        }
    }

    public var title: String {
        switch self {
        case let .song(song): song.title
        case let .video(video): video.title
        case let .cachedRadio(track): track.title
        case let .external(track): track.title
        }
    }

    public var artist: String {
        switch self {
        case let .song(song): song.artistsDisplay
        case let .video(video): video.author
        case let .cachedRadio(track): track.artist
        case let .external(track): track.artist
        }
    }

    public var artworkURL: URL? {
        switch self {
        case let .song(song): return song.thumbnailURL
        case let .video(video):
            if let urlString = video.thumbnailURL {
                return URL(string: urlString)
            }
            return nil
        case let .cachedRadio(track): return track.thumbnailURL
        case let .external(track): return track.artworkURL
        }
    }

    public var isExplicit: Bool {
        switch self {
        case let .song(song): song.isExplicit
        case .video: false
        case let .cachedRadio(track): track.isExplicit
        case let .external(track): track.isExplicit
        }
    }

    public var queueIdentity: QueueIdentitySnapshot {
        switch self {
        case let .song(song):
            return QueueIdentitySnapshot(
                canonicalID: canonicalQueueID(for: "\(song.title.lowercased())|\(song.artistsDisplay.lowercased())", fallback: song.videoId),
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        case let .video(video):
            let title = video.title.lowercased()
            let artist = video.author.lowercased()
            return QueueIdentitySnapshot(
                canonicalID: canonicalQueueID(for: "\(title)|\(artist)", fallback: video.id),
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        case let .cachedRadio(track):
            return track.queueIdentity
        case let .external(track):
            return QueueIdentitySnapshot(
                canonicalID: canonicalQueueID(for: "\(track.title.lowercased())|\(track.artist.lowercased())", fallback: track.mediaID),
                activeRepresentationKey: nil,
                hydrationState: ["metadataResolved"],
                candidateSnapshot: []
            )
        }
    }
}

public struct PreparedQueuePlayback {
    public let mediaID: String
    public let item: AVPlayerItem
    public let playbackCandidates: [PlaybackCandidate]
    public let preparedAt: Date
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let streamingService: PlayerViewModel.StreamingService
    public let qualityLabel: String
    public let codecLabel: String
    public let albumName: String?
    public let isExplicit: Bool
    public let durationHint: Int?

    public var queueIdentity: QueueIdentitySnapshot {
        let canonicalTitle = title.lowercased()
        let canonicalArtist = artist.lowercased()
        return QueueIdentitySnapshot(
            canonicalID: canonicalQueueID(for: "\(canonicalTitle)|\(canonicalArtist)", fallback: mediaID),
            activeRepresentationKey: nil,
            hydrationState: ["metadataResolved"],
            candidateSnapshot: playbackCandidates.map(QueueCandidateSnapshot.init)
        )
    }
}

public struct QueueMusicPreloadInput {
    public let mediaID: String
    public let title: String
    public let artist: String
    public let albumName: String?
    public let artworkURL: URL?
    public let isExplicit: Bool
    public let durationHint: Int?
    public let youtubeDebugSource: String
}

func canonicalQueueID(for fingerprint: String, fallback: String) -> String {
    let normalized = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? fallback : normalized
}
