//
//  ImportProgressFacade.swift
//  Library
//
//  UI-facing observable state for background imports. The Download Manager (an actor) pushes
//  snapshots here via @MainActor hops; views bind to `active`. Completion events flow over a
//  separate AsyncStream the toast listens to.
//

import Foundation
import Models
import Observation

@MainActor
@Observable
public final class ImportProgressFacade {
    public struct JobProgress: Identifiable, Sendable, Equatable {
        public let id: String          // jobID
        public let title: String
        public let provider: ImportProvider
        public let processed: Int
        public let total: Int
        public let state: PlaylistImportJobState

        public init(id: String, title: String, provider: ImportProvider, processed: Int, total: Int, state: PlaylistImportJobState) {
            self.id = id
            self.title = title
            self.provider = provider
            self.processed = processed
            self.total = total
            self.state = state
        }
    }

    public private(set) var active: [JobProgress] = []

    public init() {}

    /// Replace-or-append by jobID.
    public func upsert(_ progress: JobProgress) {
        if let idx = active.firstIndex(where: { $0.id == progress.id }) {
            active[idx] = progress
        } else {
            active.append(progress)
        }
    }

    public func remove(id: String) {
        active.removeAll { $0.id == id }
    }
}

/// Emitted once per job when it leaves the active set. The toast listens for these.
public struct ImportCompletionEvent: Sendable {
    public let jobID: String
    public let title: String
    public let destinationPlaylistID: String?
    public let state: PlaylistImportJobState
    public let matched: Int
    public let failed: Int

    public init(jobID: String, title: String, destinationPlaylistID: String?, state: PlaylistImportJobState, matched: Int, failed: Int) {
        self.jobID = jobID
        self.title = title
        self.destinationPlaylistID = destinationPlaylistID
        self.state = state
        self.matched = matched
        self.failed = failed
    }
}
