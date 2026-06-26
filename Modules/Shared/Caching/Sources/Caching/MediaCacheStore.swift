import Foundation
import Models
import os
import SwiftData

/// Minimal persisted candidate metadata (no URLs) used for auditing and canonical tracing.
private struct PersistedCandidateMetadata: Codable {
    let streamKind: String
    let mimeType: String?
    let itag: Int?
    let expiresAt: Date?
}

public struct PlaybackCandidate: Sendable, Equatable {
    public enum StreamKind: String, Sendable {
        case hls
        case muxed
        case audio
    }

    public let url: URL
    public let headers: [String: String]?
    public let streamKind: StreamKind
    public let mimeType: String?
    public let itag: Int?
    public let expiresAt: Date?
    public let isCompatible: Bool
    public let providerID: String?

    public init(
        url: URL,
        headers: [String: String]? = nil,
        streamKind: StreamKind,
        mimeType: String? = nil,
        itag: Int? = nil,
        expiresAt: Date? = nil,
        isCompatible: Bool = true,
        providerID: String? = nil
    ) {
        self.url = url
        self.headers = headers
        self.streamKind = streamKind
        self.mimeType = mimeType
        self.itag = itag
        self.expiresAt = expiresAt
        self.isCompatible = isCompatible
        self.providerID = providerID
    }
}

@ModelActor
public actor MediaCacheStore {
    public struct MotionArtworkAlbumCacheHit: Sendable {
        public let albumKey: String
        public let url: URL
    }

    public struct MaintenancePolicy: Sendable {
        public let playbackMaxAge: TimeInterval
        public let artworkURLMaxAge: TimeInterval
        public let motionArtworkMaxAge: TimeInterval
        public let localArtworkMaxAge: TimeInterval
        public let entryRetentionAge: TimeInterval
        public let maxEntries: Int

        public static let `default` = MaintenancePolicy(
            playbackMaxAge: 60 * 60 * 12,
            artworkURLMaxAge: 60 * 60 * 24 * 14,
            motionArtworkMaxAge: .greatestFiniteMagnitude,
            localArtworkMaxAge: 60 * 60 * 24 * 21,
            entryRetentionAge: 60 * 60 * 24 * 30,
            maxEntries: 600
        )
    }

    private enum MotionArtworkAlbumNamespace {
        static let mediaIDPrefix = "__motion_album__::"
    }

    private let imageFileStore: ArtworkImageFileStore = .shared

    public func playbackCandidates(for mediaID: String, maxAge: TimeInterval) async -> [PlaybackCandidate]? {
        // First check ephemeral runtime store for valid playback URLs.
        if let ephemeral = await PlaybackURLEphemeralStore.shared.candidates(for: mediaID, maxAge: maxAge) {
            // mark last access on corresponding SwiftData entry for bookkeeping
            if let entry = fetchEntry(for: mediaID) {
                entry.lastAccessedAt = .now
                saveContext()
            }
            return ephemeral
        }

        // No ephemeral URLs available; do not reconstruct candidates from
        // persisted data because URLs are ephemeral by definition.
        return nil
    }

    public func savePlaybackResolution(mediaID: String, candidates: [PlaybackCandidate], validUntil: Date?) {
        guard !candidates.isEmpty else {
            return
        }

        // Persist URLs only in the ephemeral runtime store (in-memory TTL store).
        Task { @MainActor in
            await PlaybackURLEphemeralStore.shared.save(mediaID: mediaID, candidates: candidates, expiresAt: validUntil)
        }

        // Persist minimal candidate metadata (without URLs) into SwiftData for auditing
        // and canonical tracing. This intentionally excludes absolute URLs.
        let entry = entryForWrite(mediaID: mediaID)
        entry.playbackResolvedAt = .now
        if let json = try? JSONEncoder().encode(
            candidates.map { c in
                PersistedCandidateMetadata(streamKind: c.streamKind.rawValue, mimeType: c.mimeType, itag: c.itag, expiresAt: c.expiresAt)
            }
        ), let string = String(data: json, encoding: .utf8) {
            entry.candidateMetadataJSON = string
        }

        entry.lastAccessedAt = .now
        saveContext()
    }

    public func invalidatePlayback(for mediaID: String) {
        Task { @MainActor in
            await PlaybackURLEphemeralStore.shared.invalidate(mediaID: mediaID)
        }

        guard let entry = fetchEntry(for: mediaID) else { return }
        entry.candidateMetadataJSON = nil
        entry.playbackResolvedAt = nil
        entry.lastAccessedAt = .now
        saveContext()
    }

    public func cachedHighQualityArtworkURL(for mediaID: String, maxAge: TimeInterval) -> URL? {
        guard let entry = fetchEntry(for: mediaID),
              let updatedAt = entry.artworkUpdatedAt,
              Date().timeIntervalSince(updatedAt) <= maxAge,
              let url = url(from: entry.artworkURLString)
        else {
            return nil
        }

        entry.lastAccessedAt = .now
        saveContext()
        return url
    }

    public func saveHighQualityArtworkURL(_ url: URL, for mediaID: String) {
        let entry = entryForWrite(mediaID: mediaID)
        entry.artworkURLString = url.absoluteString
        entry.artworkUpdatedAt = .now
        entry.lastAccessedAt = .now
        saveContext()
    }

    public func cachedMotionArtworkSourceURL(for mediaID: String, maxAge: TimeInterval) -> URL? {
        guard let entry = fetchEntry(for: mediaID),
              let updatedAt = entry.motionArtworkUpdatedAt,
              Date().timeIntervalSince(updatedAt) <= maxAge,
              let url = url(from: entry.motionArtworkHLSURLString)
        else {
            return nil
        }

        entry.lastAccessedAt = .now
        saveContext()
        return url
    }

    public func saveMotionArtworkSourceURL(_ url: URL, for mediaID: String) {
        let entry = entryForWrite(mediaID: mediaID)
        entry.motionArtworkHLSURLString = url.absoluteString
        entry.motionArtworkUpdatedAt = .now
        entry.lastAccessedAt = .now
        saveContext()
    }

    public func cachedMotionArtworkSourceURL(
        forAlbumKeys albumKeys: [String],
        maxAge: TimeInterval
    ) -> MotionArtworkAlbumCacheHit? {
        for albumKey in normalizedMotionArtworkAlbumKeys(albumKeys) {
            let syntheticMediaID = syntheticMotionArtworkMediaID(forAlbumKey: albumKey)
            guard let url = cachedMotionArtworkSourceURL(for: syntheticMediaID, maxAge: maxAge) else {
                continue
            }

            return MotionArtworkAlbumCacheHit(albumKey: albumKey, url: url)
        }

        return nil
    }

    public func saveMotionArtworkSourceURL(_ url: URL, forAlbumKeys albumKeys: [String]) {
        for albumKey in normalizedMotionArtworkAlbumKeys(albumKeys) {
            let syntheticMediaID = syntheticMotionArtworkMediaID(forAlbumKey: albumKey)
            saveMotionArtworkSourceURL(url, for: syntheticMediaID)
        }
    }

    public func cachedLocalArtworkData(for mediaID: String) async -> (url: URL, data: Data)? {
        guard let entry = fetchEntry(for: mediaID),
              let filename = entry.localArtworkFilename,
              let fileURL = await imageFileStore.existingFileURL(named: filename),
              let data = await imageFileStore.readData(named: filename)
        else {
            return nil
        }

        entry.lastAccessedAt = .now
        saveContext()
        return (fileURL, data)
    }

    public func saveArtworkData(_ data: Data, mediaID: String, sourceURL: URL) async -> URL? {
        guard let writeResult = await imageFileStore.write(data: data, mediaID: mediaID) else {
            return nil
        }

        let entry = entryForWrite(mediaID: mediaID)
        entry.artworkURLString = sourceURL.absoluteString
        entry.artworkUpdatedAt = .now
        entry.localArtworkFilename = writeResult.filename
        entry.localArtworkUpdatedAt = .now
        entry.lastAccessedAt = .now
        saveContext()
        return writeResult.url
    }

    public func performMaintenance(policy: MaintenancePolicy = .default) async {
        let now = Date()
        let entries = allEntries()

        for entry in entries {
            await pruneExpiredPayloads(in: entry, now: now, policy: policy)

            let hasPayload = hasAnyCachedPayload(in: entry)
            let idleTime = now.timeIntervalSince(entry.lastAccessedAt)
            if !hasPayload, idleTime > policy.entryRetentionAge {
                modelContext.delete(entry)
            }
        }

        enforceEntryLimit(policy.maxEntries)
        saveContext()

        let keepFilenames = Set(allEntries().compactMap(\.localArtworkFilename))
        await imageFileStore.pruneOrphanedFiles(
            keeping: keepFilenames,
            maxFileAge: policy.localArtworkMaxAge
        )
    }

    private func entryForWrite(mediaID: String) -> MediaCacheEntry {
        if let existing = fetchEntry(for: mediaID) {
            return existing
        }

        let created = MediaCacheEntry(mediaID: mediaID)
        modelContext.insert(created)
        return created
    }

    private func fetchEntry(for mediaID: String) -> MediaCacheEntry? {
        var descriptor = FetchDescriptor<MediaCacheEntry>(
            predicate: #Predicate { $0.mediaID == mediaID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func url(from string: String?) -> URL? {
        guard let string else { return nil }
        return URL(string: string)
    }

    private func normalizedMotionArtworkAlbumKeys(_ albumKeys: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for key in albumKeys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            normalized.append(trimmed)
        }

        return normalized
    }

    private func syntheticMotionArtworkMediaID(forAlbumKey albumKey: String) -> String {
        "\(MotionArtworkAlbumNamespace.mediaIDPrefix)\(albumKey)"
    }

    private func allEntries() -> [MediaCacheEntry] {
        let descriptor = FetchDescriptor<MediaCacheEntry>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func pruneExpiredPayloads(in entry: MediaCacheEntry, now: Date, policy: MaintenancePolicy) async {
        // Ephemeral playback URLs are pruned by the ephemeral store. Clear
        // persisted metadata if it is stale according to policy.
        if let resolvedAt = entry.playbackResolvedAt,
           now.timeIntervalSince(resolvedAt) > policy.playbackMaxAge
        {
            entry.playbackResolvedAt = nil
            entry.candidateMetadataJSON = nil
        }

        if let updatedAt = entry.artworkUpdatedAt,
           now.timeIntervalSince(updatedAt) > policy.artworkURLMaxAge
        {
            entry.artworkURLString = nil
            entry.artworkUpdatedAt = nil
        }

        if let updatedAt = entry.motionArtworkUpdatedAt,
           now.timeIntervalSince(updatedAt) > policy.motionArtworkMaxAge
        {
            entry.motionArtworkHLSURLString = nil
            entry.motionArtworkUpdatedAt = nil
        }

        var shouldClearLocalArtwork = false
        if let localUpdatedAt = entry.localArtworkUpdatedAt,
           now.timeIntervalSince(localUpdatedAt) > policy.localArtworkMaxAge
        {
            shouldClearLocalArtwork = true
        }

        if !shouldClearLocalArtwork,
           let filename = entry.localArtworkFilename
        {
            let exists = await imageFileStore.fileExists(named: filename)
            if !exists {
                shouldClearLocalArtwork = true
            }
        }

        if shouldClearLocalArtwork,
           let filename = entry.localArtworkFilename
        {
            await imageFileStore.removeFile(named: filename)
            entry.localArtworkFilename = nil
            entry.localArtworkUpdatedAt = nil
        }
    }

    private func enforceEntryLimit(_ maxEntries: Int) {
        guard maxEntries > 0 else { return }

        let sorted = allEntries().sorted { lhs, rhs in
            lhs.lastAccessedAt > rhs.lastAccessedAt
        }

        guard sorted.count > maxEntries else { return }

        for entry in sorted.dropFirst(maxEntries) {
            modelContext.delete(entry)
        }
    }

    private func hasAnyCachedPayload(in entry: MediaCacheEntry) -> Bool {
        entry.playbackResolvedAt != nil
            || entry.candidateMetadataJSON != nil
            || entry.artworkURLString != nil
            || entry.localArtworkFilename != nil
            || entry.motionArtworkHLSURLString != nil
    }

    private func saveContext() {
        try? modelContext.save()
    }
}

public actor ArtworkImageFileStore {
    public struct WriteResult: Sendable {
        public let filename: String
        public let url: URL
    }

    public typealias AppGroupContainerURLProvider = @Sendable (String) -> URL?

    public static let shared = ArtworkImageFileStore()

    private let fileManager: FileManager
    private let appGroupIdentifier: String
    private let appGroupContainerURLProvider: AppGroupContainerURLProvider

    public init(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = "group.aaravgupta.cisum",
        appGroupContainerURLProvider: @escaping AppGroupContainerURLProvider = { identifier in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    ) {
        self.fileManager = fileManager
        self.appGroupIdentifier = appGroupIdentifier
        self.appGroupContainerURLProvider = appGroupContainerURLProvider
    }

    public func write(data: Data, mediaID: String) -> WriteResult? {
        guard let directory = cacheDirectoryURL() else { return nil }

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let filename = sanitizedFilename(for: mediaID)
            let fileURL = directory.appending(path: filename)
            try data.write(to: fileURL, options: .atomic)
            return WriteResult(filename: filename, url: fileURL)
        } catch {
            return nil
        }
    }

    public func existingFileURL(named filename: String) -> URL? {
        guard let directory = cacheDirectoryURL() else { return nil }
        let fileURL = directory.appending(path: filename)

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        return fileURL
    }

    public func readData(named filename: String) async -> Data? {
        guard let fileURL = existingFileURL(named: filename) else {
            return nil
        }

        return try? await URLSession.shared.data(from: fileURL).0
    }

    public func fileExists(named filename: String) -> Bool {
        guard let fileURL = existingFileURL(named: filename) else {
            return false
        }

        return fileManager.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    public func removeFile(named filename: String) {
        guard let fileURL = existingFileURL(named: filename) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
    }

    public func pruneOrphanedFiles(keeping keepFilenames: Set<String>, maxFileAge: TimeInterval) {
        guard let directory = cacheDirectoryURL() else { return }
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        for item in items {
            let filename = item.lastPathComponent

            let isStale: Bool = if let values = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
                                   let modifiedAt = values.contentModificationDate
            {
                now.timeIntervalSince(modifiedAt) > maxFileAge
            } else {
                false
            }

            if !keepFilenames.contains(filename) || isStale {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func cacheDirectoryURL() -> URL? {
        guard let containerURL = appGroupContainerURLProvider(appGroupIdentifier) else {
            return nil
        }

        return containerURL
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Caches", directoryHint: .isDirectory)
            .appending(path: "ArtworkImages", directoryHint: .isDirectory)
    }

    private func sanitizedFilename(for mediaID: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let normalized = mediaID.map { allowed.contains($0) ? $0 : "_" }
        return String(normalized) + ".img"
    }
}
