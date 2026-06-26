//
//  AppleMusicImportService.swift
//  Library
//
//  ImportService conformance for Apple Music via MusicKit. Reads the user's library
//  playlists and their tracks (with ISRC) and emits neutral IncomingTrack DTOs.
//
//  Requires the MusicKit capability on the app's App ID and `NSAppleMusicUsageDescription`
//  in Info.plist. Compiles without them; only authorization at runtime needs them.
//

import Foundation
import Models
import Utilities

#if canImport(MusicKit)
import MusicKit

public final class AppleMusicImportService: ImportService {
    public let provider: ImportProvider = .appleMusic
    public let capabilities: ImportCapabilities = [.listsUserPlaylists, .carriesISRC]

    public init() {}

    public func isAuthorized() async -> Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    /// Prompts for Media & Apple Music access. Call before listing/importing if not authorized.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        PerfLog.info("AppleMusicImportService: requesting authorization")
        let status = await MusicAuthorization.request()
        PerfLog.info("AppleMusicImportService: authorization status=\(String(describing: status))")
        return status == .authorized
    }

    public func listImportablePlaylists(limit: Int) async throws -> [ImportablePlaylistRef] {
        PerfLog.info("AppleMusicImportService: listImportablePlaylists(limit: \(limit))")
        guard await isAuthorized() else { throw ImportError.notAuthorized }
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.limit = max(1, limit)
        let response = try await request.response()
        PerfLog.info("AppleMusicImportService: library returned \(response.items.count) playlists")
        return response.items.map { playlist in
            ImportablePlaylistRef(
                id: playlist.id.rawValue,
                title: playlist.name,
                subtitle: playlist.curatorName,
                ownerName: playlist.curatorName,
                artworkURL: playlist.artwork?.url(width: 300, height: 300),
                trackCount: nil
            )
        }
    }

    public func fetchMetadata(playlistID: String) async throws -> ImportPlaylistMetadata {
        PerfLog.info("AppleMusicImportService: fetchMetadata(\(playlistID))")
        let playlist = try await libraryPlaylist(id: playlistID)
        return ImportPlaylistMetadata(
            sourcePlaylistID: playlistID,
            title: playlist.name,
            ownerName: playlist.curatorName,
            descriptionText: playlist.standardDescription,
            artworkURL: playlist.artwork?.url(width: 600, height: 600),
            sourceURLString: playlist.url?.absoluteString,
            totalTrackCount: nil
        )
    }

    public func fetchTrackPage(playlistID: String, cursor: String?, offset: Int) async throws -> ImportTrackPage {
        PerfLog.info("AppleMusicImportService: fetchTrackPage(\(playlistID))")
        let playlist = try await libraryPlaylist(id: playlistID)
        let detailed = try await playlist.with([.tracks])
        let tracks = (detailed.tracks ?? []).map(Self.incoming(from:))
        // MusicKit returns the full track list; single page.
        return ImportTrackPage(tracks: tracks, nextCursor: nil, startOffset: offset)
    }

    // MARK: - Helpers

    private func libraryPlaylist(id: String) async throws -> MusicKit.Playlist {
        guard await isAuthorized() else { throw ImportError.notAuthorized }
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        guard let playlist = response.items.first else { throw ImportError.notFound }
        return playlist
    }

    private static func incoming(from track: Track) -> IncomingTrack {
        IncomingTrack(
            provider: .appleMusic,
            providerTrackID: track.id.rawValue,
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumTitle,
            isrc: track.isrc,
            durationSeconds: track.duration,
            artworkURLString: track.artwork?.url(width: 600, height: 600)?.absoluteString,
            isExplicit: track.contentRating == .explicit
        )
    }
}
#endif
