//
//  ImportService.swift
//  Library
//
//  Unified, extensible import abstraction. Every source (Spotify, YouTube, Apple Music,
//  Local File, and future services) conforms to this one protocol and emits the same
//  neutral `IncomingTrack` DTO that the canonical reconciler + Download Manager consume.
//
//  Lives in the Library module because Library already depends on every piece the import
//  layer needs (Models, SpotifySDK, YouTubeSDK, Playlists' stores, CentralMediaStore) and
//  is already wired into the app — no new package, no dependency cycle.
//

import Foundation
import Models

public enum ImportError: Error, Sendable {
    case notAuthorized
    case unsupported
    case notFound
    case badLink(String)
    case provider(String)
}

/// One importable music source. Maps to `MediaProvider` at the reconciliation boundary.
public protocol ImportService: Sendable {
    var provider: ImportProvider { get }
    var capabilities: ImportCapabilities { get }

    /// Cheap auth/availability check. Avoids network where possible.
    func isAuthorized() async -> Bool

    /// The user's importable playlists (empty for providers without library listing).
    func listImportablePlaylists(limit: Int) async throws -> [ImportablePlaylistRef]

    /// Resolve a link / URI / raw id (or a picked local selection) to a playlist ref.
    func resolve(link: String) async throws -> ImportablePlaylistRef

    /// Playlist header metadata, fetched before paging through its tracks.
    func fetchMetadata(playlistID: String) async throws -> ImportPlaylistMetadata

    /// One page of neutral tracks. `cursor`/`offset` come from the persisted job checkpoint.
    func fetchTrackPage(playlistID: String, cursor: String?, offset: Int) async throws -> ImportTrackPage
}

public extension ImportService {
    // Services only implement what their capabilities advertise.
    func listImportablePlaylists(limit: Int) async throws -> [ImportablePlaylistRef] {
        throw ImportError.unsupported
    }
    func resolve(link: String) async throws -> ImportablePlaylistRef {
        throw ImportError.unsupported
    }
}

extension ImportProvider {
    /// The canonical `MediaProvider` an imported track is attributed to.
    var mediaProvider: MediaProvider {
        switch self {
        case .spotify:    return .spotify
        case .youtube:    return .youtube
        case .appleMusic: return .appleMusic
        case .localFile:  return .local
        }
    }
}
