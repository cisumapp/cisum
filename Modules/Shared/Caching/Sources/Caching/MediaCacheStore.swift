import Foundation
import Models
import os
import SwiftData

@ModelActor
public actor MediaCacheStore {
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

    private let imageFileStore: ArtworkImageFileStore = .shared

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

    private func existingFileURL(named filename: String) -> URL? {
        guard let directory = cacheDirectoryURL() else { return nil }
        let fileURL = directory.appending(path: filename)

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        return fileURL
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

}
