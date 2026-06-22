import Foundation
import Models
import SwiftData
import SwiftUI

@ModelActor
public actor PlaylistLibraryStore {
    public struct PlaylistSnapshot: Sendable {
        public let playlistID: String
        public let title: String
        public let subtitle: String?
        public let descriptionText: String?
        public let artworkURLString: String?
        public let sourceProvider: PlaylistSource
        public let sourcePlaylistID: String?
        public let sourceURLString: String?
        public let sourceOwnerName: String?
        public let sourceChecksum: String?
        public let itemCount: Int
        public let importedAt: Date
        public let updatedAt: Date
        public let lastPlayedAt: Date?

        public init(
            playlistID: String = UUID().uuidString,
            title: String,
            subtitle: String? = nil,
            descriptionText: String? = nil,
            artworkURLString: String? = nil,
            sourceProvider: PlaylistSource,
            sourcePlaylistID: String? = nil,
            sourceURLString: String? = nil,
            sourceOwnerName: String? = nil,
            sourceChecksum: String? = nil,
            itemCount: Int = 0,
            importedAt: Date = .now,
            updatedAt: Date = .now,
            lastPlayedAt: Date? = nil
        ) {
            self.playlistID = playlistID
            self.title = title
            self.subtitle = subtitle
            self.descriptionText = descriptionText
            self.artworkURLString = artworkURLString
            self.sourceProvider = sourceProvider
            self.sourcePlaylistID = sourcePlaylistID
            self.sourceURLString = sourceURLString
            self.sourceOwnerName = sourceOwnerName
            self.sourceChecksum = sourceChecksum
            self.itemCount = itemCount
            self.importedAt = importedAt
            self.updatedAt = updatedAt
            self.lastPlayedAt = lastPlayedAt
        }
    }

    public struct PlaylistItemSnapshot: Sendable {
        public let sortIndex: Int
        public let sourceTrackID: String?
        public let sourceTrackFingerprint: String
        public let title: String
        public let artistName: String?
        public let albumName: String?
        public let isrc: String?
        public let durationSeconds: Double?
        public let artworkURLString: String?
        public let youtubeID: String?
        public let youtubeMusicID: String?
        public let spotifyID: String?
        public let tidalID: String?
        public var qobuzID: String?
        public let soundcloudID: String?
        public let deezerID: String?
        public let appleMusicID: String?
        public let resolutionConfidence: Double?
        public let importStatus: PlaylistItemImportStatus
        public let importErrorCode: String?
        public let importErrorMessage: String?

        public init(
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
            resolutionConfidence: Double? = nil,
            importStatus: PlaylistItemImportStatus = .pending,
            importErrorCode: String? = nil,
            importErrorMessage: String? = nil
        ) {
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
            self.resolutionConfidence = resolutionConfidence
            self.importStatus = importStatus
            self.importErrorCode = importErrorCode
            self.importErrorMessage = importErrorMessage
        }
    }

    public func playlists(limit: Int? = nil) -> [Playlist] {
        var descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\Playlist.updatedAt, order: .reverse)]
        )

        if let limit, limit > 0 {
            descriptor.fetchLimit = limit
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    public func playlist(playlistID: String) -> Playlist? {
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.playlistID == playlistID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func playlist(sourceProvider: PlaylistSource, sourcePlaylistID: String) -> Playlist? {
        let providerRawValue = sourceProvider.rawValue
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate {
                $0.sourceProviderRawValue == providerRawValue && $0.sourcePlaylistID == sourcePlaylistID
            },
            sortBy: [SortDescriptor(\Playlist.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func playlistSnapshot(playlistID: String) -> PlaylistSnapshot? {
        guard let p = playlist(playlistID: playlistID) else { return nil }
        return makeSnapshot(from: p)
    }

    public func playlistSnapshot(sourceProvider: PlaylistSource, sourcePlaylistID: String) -> PlaylistSnapshot? {
        guard let p = playlist(sourceProvider: sourceProvider, sourcePlaylistID: sourcePlaylistID) else { return nil }
        return makeSnapshot(from: p)
    }

    private func makeSnapshot(from p: Playlist) -> PlaylistSnapshot {
        PlaylistSnapshot(
            playlistID: p.playlistID,
            title: p.title,
            subtitle: p.subtitle,
            descriptionText: p.descriptionText,
            artworkURLString: p.artworkURLString,
            sourceProvider: p.sourceProvider ?? .unknown,
            sourcePlaylistID: p.sourcePlaylistID,
            sourceURLString: p.sourceURLString,
            sourceOwnerName: p.sourceOwnerName,
            sourceChecksum: p.sourceChecksum,
            itemCount: p.itemCount,
            importedAt: p.importedAt ?? .now,
            updatedAt: p.updatedAt,
            lastPlayedAt: p.lastPlayedAt
        )
    }

    public func items(for playlistID: String) -> [PlaylistItem] {
        let descriptor = FetchDescriptor<PlaylistItem>(
            predicate: #Predicate { $0.playlistID == playlistID },
            sortBy: [SortDescriptor(\PlaylistItem.sortIndex, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    public func upsertPlaylist(_ snapshot: PlaylistSnapshot) {
        let entry = playlist(playlistID: snapshot.playlistID) ?? {
            let created = Playlist(
                playlistID: snapshot.playlistID,
                title: snapshot.title,
                normalizedTitle: snapshot.title.lowercased(),
                subtitle: snapshot.subtitle,
                descriptionText: snapshot.descriptionText,
                artworkURLString: snapshot.artworkURLString,
                sourceProvider: snapshot.sourceProvider,
                sourcePlaylistID: snapshot.sourcePlaylistID,
                sourceURLString: snapshot.sourceURLString,
                sourceOwnerName: snapshot.sourceOwnerName,
                sourceChecksum: snapshot.sourceChecksum,
                itemCount: snapshot.itemCount,
                importedAt: snapshot.importedAt,
                updatedAt: snapshot.updatedAt,
                lastPlayedAt: snapshot.lastPlayedAt
            )
            modelContext.insert(created)
            return created
        }()

        entry.title = snapshot.title
        entry.subtitle = snapshot.subtitle
        entry.descriptionText = snapshot.descriptionText
        entry.artworkURLString = snapshot.artworkURLString
        entry.sourceProvider = snapshot.sourceProvider
        entry.sourcePlaylistID = snapshot.sourcePlaylistID
        entry.sourceURLString = snapshot.sourceURLString
        entry.sourceOwnerName = snapshot.sourceOwnerName
        entry.sourceChecksum = snapshot.sourceChecksum
        entry.itemCount = snapshot.itemCount
        entry.importedAt = snapshot.importedAt
        entry.updatedAt = snapshot.updatedAt
        entry.lastPlayedAt = snapshot.lastPlayedAt
        saveContext()
    }

    public func replaceItems(for playlistID: String, with snapshots: [PlaylistItemSnapshot]) {
        let existingItems = items(for: playlistID)
        for item in existingItems {
            modelContext.delete(item)
        }
        saveContext()

        let sorted = snapshots.sorted(by: { $0.sortIndex < $1.sortIndex })
        let batchSize = 200
        
        for batch in sorted.chunked(into: batchSize) {
            for snapshot in batch {
                let created = PlaylistItem(
                    playlistID: playlistID,
                    sortIndex: snapshot.sortIndex,
                    sourceTrackID: snapshot.sourceTrackID,
                    sourceTrackFingerprint: snapshot.sourceTrackFingerprint,
                    title: snapshot.title,
                    artistName: snapshot.artistName,
                    albumName: snapshot.albumName,
                    isrc: snapshot.isrc,
                    durationSeconds: snapshot.durationSeconds,
                    artworkURLString: snapshot.artworkURLString,
                    youtubeID: snapshot.youtubeID,
                    youtubeMusicID: snapshot.youtubeMusicID,
                    spotifyID: snapshot.spotifyID,
                    tidalID: snapshot.tidalID,
                    qobuzID: snapshot.qobuzID,
                    soundcloudID: snapshot.soundcloudID,
                    deezerID: snapshot.deezerID,
                    appleMusicID: snapshot.appleMusicID,
                    resolutionConfidence: snapshot.resolutionConfidence,
                    importStatus: snapshot.importStatus,
                    importErrorCode: snapshot.importErrorCode,
                    importErrorMessage: snapshot.importErrorMessage,
                    createdAt: .now,
                    updatedAt: .now
                )
                modelContext.insert(created)
            }
            saveContext()
        }

        if let playlist = playlist(playlistID: playlistID) {
            playlist.itemCount = snapshots.count
            playlist.updatedAt = .now
        }

        saveContext()
    }

    public func deletePlaylist(playlistID: String) {
        for item in items(for: playlistID) {
            modelContext.delete(item)
        }

        if let playlist = playlist(playlistID: playlistID) {
            modelContext.delete(playlist)
        }

        saveContext()
    }

    public func markPlaylistPlayed(playlistID: String, playedAt: Date = .now) {
        guard let playlist = playlist(playlistID: playlistID) else {
            return
        }

        playlist.lastPlayedAt = playedAt
        playlist.updatedAt = .now
        saveContext()
    }

    public func updateProviderID(for itemKey: String, provider: String, trackID: String) {
        var descriptor = FetchDescriptor<PlaylistItem>(
            predicate: #Predicate { $0.itemKey == itemKey }
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        switch provider.lowercased() {
        case "youtube": item.youtubeID = trackID
        case "youtubemusic", "youtube_music": item.youtubeMusicID = trackID
        case "spotify": item.spotifyID = trackID
        case "tidal": item.tidalID = trackID
        case "qobuz": item.qobuzID = trackID
        case "soundcloud": item.soundcloudID = trackID
        case "deezer": item.deezerID = trackID
        case "applemusic", "apple_music": item.appleMusicID = trackID
        default: break
        }

        item.updatedAt = .now

        if let playlist = playlist(playlistID: item.playlistID) {
            playlist.updatedAt = .now
        }

        saveContext()
    }

    private func saveContext() {
        try? modelContext.save()
    }
}

// MARK: - Environment Key

public struct PlaylistLibraryStoreKey: EnvironmentKey {
    public static let defaultValue: PlaylistLibraryStore? = nil
}

public extension EnvironmentValues {
    var playlistLibraryStore: PlaylistLibraryStore? {
        get { self[PlaylistLibraryStoreKey.self] }
        set { self[PlaylistLibraryStoreKey.self] = newValue }
    }
}
