//
//  SpotifyImportService.swift
//  Library
//
//  ImportService conformance for Spotify. Wraps the same SpotifySDK calls the legacy
//  SpotifyPlaylistImportService used, but emits neutral IncomingTrack DTOs.
//

import Foundation
import Models
import Utilities

#if canImport(SpotifySDK)
import SpotifySDK
import Playlists  // SpotifyPlaylistURLParser

/// Stable synthetic id for the user's Liked Songs collection.
private let spotifyLikedSongsPlaylistID = "spotify:collection:tracks"

public final class SpotifyImportService: ImportService {
    public let provider: ImportProvider = .spotify
    public let capabilities: ImportCapabilities = [.listsUserPlaylists, .importByLink, .likedSongs, .carriesISRC]

    // SDK is session-dependent (nil before auth, replaced on re-auth), so fetch it lazily.
    private let sdkProvider: @MainActor @Sendable () -> SpotifySDK?
    private let authCheck: @Sendable () async -> Bool

    public init(
        sdkProvider: @escaping @MainActor @Sendable () -> SpotifySDK?,
        isAuthorized: @escaping @Sendable () async -> Bool
    ) {
        self.sdkProvider = sdkProvider
        self.authCheck = isAuthorized
    }

    public func isAuthorized() async -> Bool {
        await authCheck()
    }

    private func currentSDK() async throws -> SpotifySDK {
        guard let sdk = await sdkProvider() else { throw ImportError.notAuthorized }
        return sdk
    }

    public func listImportablePlaylists(limit: Int) async throws -> [ImportablePlaylistRef] {
        PerfLog.info("SpotifyImportService: listImportablePlaylists(limit: \(limit))")
        let sdk = try await currentSDK()
        let summaries = try await sdk.account.playlists(limit: max(1, limit))
        PerfLog.info("SpotifyImportService: SDK returned \(summaries.count) playlists")
        return summaries.map { s in
            ImportablePlaylistRef(
                id: SpotifyPlaylistURLParser.extractPlaylistID(from: s.uri) ?? s.uri,
                title: s.name,
                subtitle: nil,
                ownerName: s.ownerDisplayName ?? s.ownerUsername,
                artworkURL: s.artworkURL,
                trackCount: s.trackCount
            )
        }
    }

    public func resolve(link: String) async throws -> ImportablePlaylistRef {
        PerfLog.info("SpotifyImportService: resolve(link:)")
        guard let id = SpotifyPlaylistURLParser.extractPlaylistID(from: link) else {
            throw ImportError.badLink(link)
        }
        let meta = try await fetchMetadata(playlistID: id)
        return ImportablePlaylistRef(
            id: id, title: meta.title, subtitle: nil,
            ownerName: meta.ownerName, artworkURL: meta.artworkURL, trackCount: meta.totalTrackCount
        )
    }

    public func fetchMetadata(playlistID: String) async throws -> ImportPlaylistMetadata {
        PerfLog.info("SpotifyImportService: fetchMetadata(\(playlistID))")
        let sdk = try await currentSDK()
        if playlistID == spotifyLikedSongsPlaylistID {
            let page = try await sdk.account.likedSongs(limit: 1)
            return ImportPlaylistMetadata(
                sourcePlaylistID: spotifyLikedSongsPlaylistID,
                title: "Liked Songs",
                totalTrackCount: page.totalCount ?? page.items.count
            )
        }
        let playlist = try await sdk.playlists.details(id: playlistID)
        return ImportPlaylistMetadata(
            sourcePlaylistID: playlist.id,
            title: playlist.name,
            ownerName: playlist.owner?.displayName,
            descriptionText: playlist.description,
            artworkURL: playlist.images.first?.url,
            sourceURLString: playlist.uri.isEmpty ? nil : playlist.uri,
            totalTrackCount: playlist.totalTracks ?? playlist.tracks?.items.count
        )
    }

    public func fetchTrackPage(playlistID: String, cursor: String?, offset: Int) async throws -> ImportTrackPage {
        PerfLog.info("SpotifyImportService: fetchTrackPage(\(playlistID), offset: \(offset))")
        let sdk = try await currentSDK()

        // Liked Songs is genuinely paged (cursor = next offset as string).
        if playlistID == spotifyLikedSongsPlaylistID {
            let pageSize = 100
            let page = try await sdk.account.likedSongs(offset: offset, limit: pageSize)
            let tracks = page.items.map(\.track).map(Self.incoming(from:))
            let nextOffset = offset + tracks.count
            let total = page.totalCount ?? nextOffset
            let hasMore = !page.items.isEmpty && nextOffset < total
            return ImportTrackPage(
                tracks: tracks,
                nextCursor: hasMore ? String(nextOffset) : nil,
                startOffset: offset
            )
        }

        // Normal playlists: detailsWithAllTracks fetches the full track list in one shot.
        let playlist = try await sdk.playlists.detailsWithAllTracks(id: playlistID)
        let tracks = (playlist.tracks?.items ?? []).map(Self.incoming(from:))
        return await PerfLog.measure("SpotifyImportService.page(\(tracks.count))") {
            ImportTrackPage(tracks: tracks, nextCursor: nil, startOffset: offset)
        }
    }

    private static func incoming(from track: SpotifyTrack) -> IncomingTrack {
        IncomingTrack(
            provider: .spotify,
            providerTrackID: track.id,
            title: track.name,
            artistName: track.artists.first?.name,
            albumName: track.album?.name,
            isrc: track.externalIDs?["isrc"],
            durationSeconds: track.durationMS > 0 ? Double(track.durationMS) / 1000.0 : nil,
            artworkURLString: track.album?.images.first?.url.absoluteString,
            isExplicit: track.isExplicit ?? false,
            spotifyTrackURI: track.uri,
            spotifyPreviewURLString: track.previewURL?.absoluteString
        )
    }
}
#endif
