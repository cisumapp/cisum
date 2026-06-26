//
//  ImportDownloadManager.swift
//  Library
//
//  Background metadata-import engine. Drives the (previously unused) PlaylistImportJobStore:
//  queues playlists, pages tracks off the main actor, reconciles each into a canonical Song
//  (ISRC dedup), writes items via PlaylistLibraryStore, checkpoints per page, and reports
//  progress + completion to the UI. Partial failures are logged, never abort the job.
//
//  Resume policy (ponytail): pending jobs restart from page 0 on relaunch. Re-fetch is
//  idempotent (replaceItems replaces); single-page providers make mid-offset resume moot.
//

import Foundation
import Models
import Utilities
import Playlists

public actor ImportDownloadManager {
    private struct QueuedJob: Sendable {
        let jobID: String
        let provider: ImportProvider
        let ref: ImportablePlaylistRef
    }

    private let jobStore: PlaylistImportJobStore
    private let centralMediaStore: CentralMediaStore
    private let playlistLibraryStore: PlaylistLibraryStore
    private let services: [ImportProvider: any ImportService]
    private let progress: ImportProgressFacade
    private let maxConcurrentJobs: Int

    private var queue: [QueuedJob] = []
    private var runningCount = 0
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cancelled: Set<String> = []

    public nonisolated let completions: AsyncStream<ImportCompletionEvent>
    private nonisolated let continuation: AsyncStream<ImportCompletionEvent>.Continuation

    public init(
        jobStore: PlaylistImportJobStore,
        centralMediaStore: CentralMediaStore,
        playlistLibraryStore: PlaylistLibraryStore,
        services: [ImportProvider: any ImportService],
        progress: ImportProgressFacade,
        maxConcurrentJobs: Int = 2
    ) {
        self.jobStore = jobStore
        self.centralMediaStore = centralMediaStore
        self.playlistLibraryStore = playlistLibraryStore
        self.services = services
        self.progress = progress
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)

        var cont: AsyncStream<ImportCompletionEvent>.Continuation!
        self.completions = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Public API

    @discardableResult
    public func enqueue(provider: ImportProvider, playlistRef ref: ImportablePlaylistRef) async -> String {
        let src = Self.playlistSource(provider)
        let jobID = await jobStore.ensureJob(.init(
            idempotencyKey: "\(provider.rawValue):\(ref.id)",
            sourceProvider: src,
            sourcePlaylistID: ref.id,
            sourcePlaylistName: ref.title,
            state: .queued,
            totalTrackCount: ref.trackCount ?? 0
        ))
        await progress.upsert(.init(id: jobID, title: ref.title, provider: provider, processed: 0, total: ref.trackCount ?? 0, state: .queued))
        queue.append(QueuedJob(jobID: jobID, provider: provider, ref: ref))
        PerfLog.info("ImportDownloadManager: enqueued job=\(jobID) provider=\(provider.rawValue) playlist=\(ref.title)")
        drain()
        return jobID
    }

    @discardableResult
    public func enqueue(provider: ImportProvider, playlistRefs refs: [ImportablePlaylistRef]) async -> [String] {
        var ids: [String] = []
        for ref in refs {
            ids.append(await enqueue(provider: provider, playlistRef: ref))
        }
        return ids
    }

    /// The registered service for a provider (so UI shares the same instances).
    public func service(for provider: ImportProvider) -> (any ImportService)? {
        services[provider]
    }

    public func cancel(jobID: String) {
        cancelled.insert(jobID)
        tasks[jobID]?.cancel()
        PerfLog.info("ImportDownloadManager: cancel requested job=\(jobID)")
    }

    public func cancelAll() {
        for id in tasks.keys { cancel(jobID: id) }
        queue.removeAll()
    }

    /// Re-run interrupted jobs at launch. Idempotent: ensureJob reuses the same job row.
    public func resumePendingJobs() async {
        let snapshots = await jobStore.pendingJobSnapshots()
        guard !snapshots.isEmpty else { return }
        PerfLog.info("ImportDownloadManager: resuming \(snapshots.count) pending job(s)")
        for snap in snapshots {
            let provider = Self.importProvider(for: snap)
            let ref = ImportablePlaylistRef(
                id: snap.sourcePlaylistID,
                title: snap.sourcePlaylistName ?? "Imported Playlist",
                trackCount: snap.totalTrackCount > 0 ? snap.totalTrackCount : nil
            )
            await enqueue(provider: provider, playlistRef: ref)
        }
    }

    // MARK: - Scheduler

    private func drain() {
        while runningCount < maxConcurrentJobs, !queue.isEmpty {
            let job = queue.removeFirst()
            runningCount += 1
            let task = Task { [self] in
                await run(job)
                await jobFinished(job.jobID)
            }
            tasks[job.jobID] = task
        }
    }

    private func jobFinished(_ jobID: String) {
        runningCount = max(0, runningCount - 1)
        tasks[jobID] = nil
        cancelled.remove(jobID)
        drain()
    }

    // MARK: - Job execution

    private func run(_ job: QueuedJob) async {
        let jobID = job.jobID
        let ref = job.ref
        guard let service = services[job.provider] else {
            PerfLog.error("ImportDownloadManager: no service for \(job.provider.rawValue)")
            await jobStore.finish(jobID: jobID, state: .failed, destinationPlaylistID: nil,
                                  lastErrorCode: "no_service", lastErrorMessage: "No import service registered.")
            await complete(jobID: jobID, title: ref.title, destinationPlaylistID: nil, state: .failed, matched: 0, failed: 0)
            return
        }

        let src = Self.playlistSource(job.provider)
        let existing = await playlistLibraryStore.playlistSnapshot(sourceProvider: src, sourcePlaylistID: ref.id)
        let destID = existing?.playlistID ?? UUID().uuidString

        var title = ref.title
        var items: [PlaylistLibraryStore.PlaylistItemSnapshot] = []
        var trackEntries: [PlaylistImportJobStore.TrackSnapshot] = []
        var processed = 0, matched = 0, failed = 0

        PerfLog.info("ImportDownloadManager: job start \(jobID) dest=\(destID)")

        do {
            let meta = try await service.fetchMetadata(playlistID: ref.id)
            title = meta.title
            let total = meta.totalTrackCount ?? ref.trackCount ?? 0
            await progress.upsert(.init(id: jobID, title: title, provider: job.provider, processed: 0, total: total, state: .running))

            await playlistLibraryStore.upsertPlaylist(.init(
                playlistID: destID,
                title: title,
                subtitle: meta.ownerName.map { "by \($0)" },
                descriptionText: meta.descriptionText,
                artworkURLString: meta.artworkURL?.absoluteString,
                sourceProvider: src,
                sourcePlaylistID: ref.id,
                sourceURLString: meta.sourceURLString,
                sourceOwnerName: meta.ownerName,
                itemCount: total,
                importedAt: existing?.importedAt ?? .now
            ))

            var cursor: String?
            var offset = 0
            while true {
                if cancelled.contains(jobID) {
                    await jobStore.finish(jobID: jobID, state: .cancelled, destinationPlaylistID: destID)
                    await complete(jobID: jobID, title: title, destinationPlaylistID: destID, state: .cancelled, matched: matched, failed: failed)
                    PerfLog.info("ImportDownloadManager: job cancelled \(jobID)")
                    return
                }

                let page = try await service.fetchTrackPage(playlistID: ref.id, cursor: cursor, offset: offset)
                for incoming in page.tracks {
                    let idx = items.count
                    if incoming.providerTrackID.isEmpty, incoming.title.isEmpty {
                        failed += 1
                        items.append(Self.failedItem(at: idx))
                        trackEntries.append(.init(jobID: jobID, sourceTrackFingerprint: "empty-\(idx)", sourceIndex: idx,
                                                  title: "Unknown", state: .failed, errorCode: "empty",
                                                  errorMessage: "Track had no identity."))
                        PerfLog.warning("ImportDownloadManager: job \(jobID) skipped empty track at \(idx)")
                    } else {
                        let songID = await centralMediaStore.reconcile(incoming)
                        matched += 1
                        items.append(Self.itemSnapshot(from: incoming, sortIndex: idx, canonicalSongID: songID))
                        trackEntries.append(Self.trackSnapshot(from: incoming, jobID: jobID, sourceIndex: idx, canonicalSongID: songID))
                    }
                    processed += 1
                }

                offset += page.tracks.count
                cursor = page.nextCursor
                await jobStore.checkpoint(jobID: jobID, nextTrackOffset: offset, resumeToken: cursor,
                                          processedTrackCount: processed, matchedTrackCount: matched,
                                          uncertainTrackCount: 0, failedTrackCount: failed, requiresReview: false)
                await progress.upsert(.init(id: jobID, title: title, provider: job.provider, processed: processed, total: max(total, processed), state: .running))
                PerfLog.debug("ImportDownloadManager: job \(jobID) page committed processed=\(processed)")
                if cursor == nil { break }
            }

            // Finalize.
            await playlistLibraryStore.replaceItems(for: destID, with: items)
            await jobStore.replaceTracks(for: jobID, with: trackEntries)
            let finalState: PlaylistImportJobState = failed == 0 ? .completed : .partialFailure
            await jobStore.finish(jobID: jobID, state: finalState, destinationPlaylistID: destID)
            await complete(jobID: jobID, title: title, destinationPlaylistID: destID, state: finalState, matched: matched, failed: failed)
            PerfLog.info("ImportDownloadManager: job done \(jobID) state=\(finalState.rawValue) matched=\(matched) failed=\(failed)")
        } catch {
            // Page fetch threw. Keep whatever we already reconciled (partial), else fail.
            if processed > 0 {
                await playlistLibraryStore.replaceItems(for: destID, with: items)
                await jobStore.replaceTracks(for: jobID, with: trackEntries)
                await jobStore.finish(jobID: jobID, state: .partialFailure, destinationPlaylistID: destID,
                                      lastErrorCode: "page_fetch", lastErrorMessage: error.localizedDescription)
                await complete(jobID: jobID, title: title, destinationPlaylistID: destID, state: .partialFailure, matched: matched, failed: failed)
                PerfLog.warning("ImportDownloadManager: job \(jobID) partial-failure: \(error.localizedDescription)")
            } else {
                await jobStore.finish(jobID: jobID, state: .failed, destinationPlaylistID: nil,
                                      lastErrorCode: "fetch", lastErrorMessage: error.localizedDescription)
                await complete(jobID: jobID, title: title, destinationPlaylistID: nil, state: .failed, matched: 0, failed: 0)
                PerfLog.error("ImportDownloadManager: job \(jobID) failed: \(error.localizedDescription)")
            }
        }
    }

    private func complete(jobID: String, title: String, destinationPlaylistID: String?, state: PlaylistImportJobState, matched: Int, failed: Int) async {
        continuation.yield(ImportCompletionEvent(jobID: jobID, title: title, destinationPlaylistID: destinationPlaylistID, state: state, matched: matched, failed: failed))
        await progress.remove(id: jobID)
    }

    // MARK: - Mapping helpers

    private static func itemSnapshot(from t: IncomingTrack, sortIndex: Int, canonicalSongID: String) -> PlaylistLibraryStore.PlaylistItemSnapshot {
        PlaylistLibraryStore.PlaylistItemSnapshot(
            sortIndex: sortIndex,
            sourceTrackID: t.providerTrackID,
            sourceTrackFingerprint: "\(t.title)|\(t.artistName ?? "")".lowercased(),
            title: t.title,
            artistName: t.artistName,
            albumName: t.albumName,
            isrc: t.isrc,
            durationSeconds: t.durationSeconds,
            artworkURLString: t.artworkURLString,
            youtubeID: t.provider == .youtube ? t.providerTrackID : nil,
            youtubeMusicID: t.provider == .youtubeMusic ? t.providerTrackID : nil,
            spotifyID: t.provider == .spotify ? t.providerTrackID : nil,
            appleMusicID: t.provider == .appleMusic ? t.providerTrackID : nil,
            resolutionConfidence: 1,
            canonicalSongID: canonicalSongID,
            importStatus: .matched
        )
    }

    private static func failedItem(at sortIndex: Int) -> PlaylistLibraryStore.PlaylistItemSnapshot {
        PlaylistLibraryStore.PlaylistItemSnapshot(
            sortIndex: sortIndex,
            sourceTrackFingerprint: "empty-\(sortIndex)",
            title: "Unknown Track",
            importStatus: .failed,
            importErrorCode: "empty",
            importErrorMessage: "Track had no identity."
        )
    }

    private static func trackSnapshot(from t: IncomingTrack, jobID: String, sourceIndex: Int, canonicalSongID: String) -> PlaylistImportJobStore.TrackSnapshot {
        PlaylistImportJobStore.TrackSnapshot(
            jobID: jobID,
            sourceTrackID: t.providerTrackID,
            sourceTrackFingerprint: "\(t.title)|\(t.artistName ?? "")".lowercased(),
            sourceIndex: sourceIndex,
            title: t.title,
            artistName: t.artistName,
            albumName: t.albumName,
            durationSeconds: t.durationSeconds,
            state: .resolved,
            youtubeID: t.provider == .youtube ? t.providerTrackID : nil,
            youtubeMusicID: t.provider == .youtubeMusic ? t.providerTrackID : nil,
            spotifyID: t.provider == .spotify ? t.providerTrackID : nil,
            appleMusicID: t.provider == .appleMusic ? t.providerTrackID : nil,
            canonicalSongID: canonicalSongID,
            confidenceScore: 1
        )
    }

    private static func playlistSource(_ p: ImportProvider) -> PlaylistSource {
        switch p {
        case .spotify:    return .spotify
        case .youtube:    return .youtube
        case .appleMusic: return .appleMusic
        case .localFile:  return .unknown
        }
    }

    private static func importProvider(for snap: PlaylistImportJobStore.JobSnapshot) -> ImportProvider {
        if snap.sourcePlaylistID.hasPrefix("local:") { return .localFile }
        switch snap.sourceProvider {
        case .spotify: return .spotify
        case .appleMusic: return .appleMusic
        case .youtube, .youtubeMusic: return .youtube
        default: return .youtube
        }
    }
}
