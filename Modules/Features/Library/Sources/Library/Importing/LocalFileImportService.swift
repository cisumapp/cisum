//
//  LocalFileImportService.swift
//  Library
//
//  ImportService conformance for local audio files picked via the document picker.
//  Reads tag metadata (title/artist/album/duration/ISRC) with AVFoundation and emits
//  neutral IncomingTrack DTOs. Metadata only — no audio is copied.
//
//  ponytail: local-file *playback* is out of scope (decision: stream-on-demand). Only
//  metadata is imported; add a disk-playback path when local playback is actually requested.
//

import Foundation
import AVFoundation
import Models
import Utilities

public final class LocalFileImportService: ImportService {
    public let provider: ImportProvider = .localFile
    public let capabilities: ImportCapabilities = [.importByLink]

    public init() {}

    /// Always available — the document picker is user-initiated.
    public func isAuthorized() async -> Bool { true }

    /// Register a user's picked audio files as a synthetic playlist. Persists security-scoped
    /// bookmarks (keyed by the returned id) so the import survives app relaunch.
    public func register(urls: [URL], title: String) throws -> ImportablePlaylistRef {
        PerfLog.info("LocalFileImportService: register \(urls.count) file(s)")
        let bookmarks: [Data] = urls.compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        let playlistID = "local:" + UUID().uuidString
        try Self.store.save(.init(title: title, bookmarks: bookmarks), id: playlistID)
        return ImportablePlaylistRef(id: playlistID, title: title, trackCount: bookmarks.count)
    }

    public func fetchMetadata(playlistID: String) async throws -> ImportPlaylistMetadata {
        PerfLog.info("LocalFileImportService: fetchMetadata(\(playlistID))")
        guard let entry = try Self.store.load(id: playlistID) else { throw ImportError.notFound }
        return ImportPlaylistMetadata(
            sourcePlaylistID: playlistID,
            title: entry.title,
            totalTrackCount: entry.bookmarks.count
        )
    }

    public func fetchTrackPage(playlistID: String, cursor: String?, offset: Int) async throws -> ImportTrackPage {
        PerfLog.info("LocalFileImportService: fetchTrackPage(\(playlistID))")
        guard let entry = try Self.store.load(id: playlistID) else { throw ImportError.notFound }

        var tracks: [IncomingTrack] = []
        for (index, bookmark) in entry.bookmarks.enumerated() {
            guard let track = await Self.readTrack(bookmark: bookmark, index: index) else {
                PerfLog.warning("LocalFileImportService: skipped unreadable file at index \(index)")
                continue
            }
            tracks.append(track)
        }
        return ImportTrackPage(tracks: tracks, nextCursor: nil, startOffset: offset)
    }

    // MARK: - Metadata extraction

    private static func readTrack(bookmark: Data, index: Int) async -> IncomingTrack? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []

        let title = await string(for: .commonIdentifierTitle, in: metadata) ?? url.deletingPathExtension().lastPathComponent
        let artist = await string(for: .commonIdentifierArtist, in: metadata)
        let album = await string(for: .commonIdentifierAlbumName, in: metadata)
        let isrc = await string(for: .id3MetadataInternationalStandardRecordingCode, in: metadata)

        var duration: Double?
        if let cm = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cm)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }

        return IncomingTrack(
            provider: .local,
            providerTrackID: url.absoluteString,  // stable per-file id
            title: title,
            artistName: artist,
            albumName: album,
            isrc: isrc.flatMap { $0.isEmpty ? nil : $0 },
            durationSeconds: duration,
            artworkURLString: nil  // embedded artwork has no URL; resolved at display time if needed
        )
    }

    private static func string(for identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
            return nil
        }
        return try? await item.load(.stringValue)
    }

    // MARK: - Bookmark persistence

    struct Entry: Codable, Sendable {
        let title: String
        let bookmarks: [Data]
    }

    private static let store = BookmarkStore()

    struct BookmarkStore: Sendable {
        private var directory: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return base.appendingPathComponent("cisum/local-imports", isDirectory: true)
        }

        func save(_ entry: Entry, id: String) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL(id: id), options: .atomic)
        }

        func load(id: String) throws -> Entry? {
            let url = fileURL(id: id)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url))
        }

        private func fileURL(id: String) -> URL {
            let safe = id.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            return directory.appendingPathComponent("\(safe).json")
        }
    }
}
