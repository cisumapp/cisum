//
//  YouTubeImportService.swift
//  Library
//
//  ImportService conformance for YouTube / YouTube Music. Mirrors the legacy
//  YouTubePlaylistImportService's main→music fallback, emitting neutral IncomingTrack DTOs.
//  YouTube carries no ISRC, so reconciliation falls back to fuzzy title/artist/duration matching.
//

import Foundation
import Models
import Utilities
import YouTubeSDK

public final class YouTubeImportService: ImportService {
    public let provider: ImportProvider = .youtube
    public let capabilities: ImportCapabilities = [.importByLink]

    private let youtube: YouTube

    public init(youtube: YouTube) {
        self.youtube = youtube
    }

    /// Public playlists resolve without auth, so import is always available.
    public func isAuthorized() async -> Bool { true }

    public func resolve(link: String) async throws -> ImportablePlaylistRef {
        PerfLog.info("YouTubeImportService: resolve(link:)")
        let id = try Self.parsePlaylistID(from: link)
        let meta = try await fetchMetadata(playlistID: id)
        return ImportablePlaylistRef(
            id: id, title: meta.title, subtitle: nil,
            ownerName: meta.ownerName, artworkURL: meta.artworkURL, trackCount: meta.totalTrackCount
        )
    }

    public func fetchMetadata(playlistID: String) async throws -> ImportPlaylistMetadata {
        PerfLog.info("YouTubeImportService: fetchMetadata(\(playlistID))")
        // Best-effort header via search; never fatal if it misses.
        let info = await lookupPlaylist(for: playlistID)
        return ImportPlaylistMetadata(
            sourcePlaylistID: playlistID,
            title: info?.title ?? "YouTube Playlist",
            ownerName: info?.author,
            artworkURL: info?.thumbnailURL,
            sourceURLString: "https://www.youtube.com/playlist?list=\(playlistID)",
            totalTrackCount: nil
        )
    }

    public func fetchTrackPage(playlistID: String, cursor: String?, offset: Int) async throws -> ImportTrackPage {
        PerfLog.info("YouTubeImportService: fetchTrackPage(\(playlistID))")
        let tracks = try await PerfLog.measure("YouTubeImportService.fetchAll") {
            try await fetchAllTracks(playlistID: playlistID)
        }
        guard !tracks.isEmpty else { throw ImportError.notFound }
        // YouTube playlists are loaded in full here; single page.
        return ImportTrackPage(tracks: tracks, nextCursor: nil, startOffset: offset)
    }

    // MARK: - Fetching

    private func fetchAllTracks(playlistID: String) async throws -> [IncomingTrack] {
        if let main = try await fetchFromMain(playlistID: playlistID), !main.isEmpty {
            return main
        }
        if let music = await fetchFromMusic(playlistID: playlistID), !music.isEmpty {
            return music
        }
        return []
    }

    private func fetchFromMain(playlistID: String, maxPages: Int = 12) async throws -> [IncomingTrack]? {
        let firstPage: YouTubeContinuation<YouTubeVideo>
        do {
            firstPage = try await youtube.main.getPlaylist(id: playlistID)
        } catch {
            return nil
        }

        var out: [IncomingTrack] = []
        var seen = Set<String>()
        func ingest(_ items: [YouTubeVideo]) {
            for video in items {
                let id = video.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                out.append(IncomingTrack(
                    provider: .youtube,
                    providerTrackID: id,
                    title: video.title,
                    artistName: video.author,
                    durationSeconds: Self.parseDuration(video.lengthInSeconds),
                    artworkURLString: video.thumbnailURL
                ))
            }
        }

        ingest(firstPage.items)
        var token = firstPage.continuationToken
        var pages = 0
        while let t = token, !t.isEmpty, pages < maxPages {
            pages += 1
            let page = try await youtube.main.getPlaylist(id: playlistID)
            ingest(page.items)
            token = page.continuationToken
        }
        return out
    }

    private func fetchFromMusic(playlistID: String) async -> [IncomingTrack]? {
        let songs: [YouTubeMusicSong]
        do {
            songs = try await youtube.music.getPlaylist(browseId: playlistID)
        } catch {
            return nil
        }
        return songs.compactMap { song in
            let id = song.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            return IncomingTrack(
                provider: .youtubeMusic,
                providerTrackID: id,
                title: song.title,
                artistName: song.artistsDisplay,
                albumName: song.album,
                durationSeconds: song.duration,
                artworkURLString: song.thumbnailURL?.absoluteString
            )
        }
    }

    private func lookupPlaylist(for playlistID: String) async -> (title: String, author: String?, thumbnailURL: URL?)? {
        guard let continuation = try? await youtube.main.search(playlistID) else { return nil }
        let playlists = continuation.items.compactMap { item -> YouTubePlaylist? in
            guard case let .playlist(p) = item else { return nil }
            return p
        }
        guard let match = playlists.first(where: { $0.id == playlistID }) ?? playlists.first else { return nil }
        return (match.title, match.author, match.thumbnailURL)
    }

    // MARK: - Helpers

    static func parsePlaylistID(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.badLink(raw) }

        // Raw playlist ID.
        if trimmed.range(of: "^[A-Za-z0-9_-]{10,}$", options: .regularExpression) != nil,
           !trimmed.contains("/")
        {
            return trimmed
        }

        let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: normalized),
              let list = comps.queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty
        else {
            throw ImportError.badLink(raw)
        }
        return list
    }

    static func parseDuration(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let s = Double(trimmed), s > 0 { return s }
        let parts = trimmed.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}
