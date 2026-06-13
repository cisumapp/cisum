import Foundation
import Models

public final class QueuePersistenceStore: @unchecked Sendable {
    public static let lastQueueKey = "__last_active_queue__"

    private let fileManager: FileManager
    private let fileURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Correct precedence: evaluate the base URL first
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        
        let directory = base
            .appendingPathComponent("cisum", isDirectory: true)
            .appendingPathComponent("Queue", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("last_queue.json")
        
        // Migration: move legacy queue files to the new correct location if it doesn't already exist
        if !fileManager.fileExists(atPath: self.fileURL.path) {
            let legacyPaths = [
                base.appendingPathComponent("last_queue.json"), // from precedence bug
                base.appendingPathComponent("Cisum").appendingPathComponent("Queue").appendingPathComponent("last_queue.json") // from old capitalization
            ]
            
            for oldPath in legacyPaths {
                if fileManager.fileExists(atPath: oldPath.path) {
                    try? fileManager.moveItem(at: oldPath, to: self.fileURL)
                    break // Migrated successfully
                }
            }
        }
    }

    public func saveLastSession(state: PersistedTrackState) {
        Task.detached { [fileURL = self.fileURL] in
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    public func loadLastSession() async -> PersistedTrackState? {
        await Task.detached { [fileURL = self.fileURL] in
            guard let data = try? Data(contentsOf: fileURL),
                  let state = try? JSONDecoder().decode(PersistedTrackState.self, from: data)
            else {
                return nil
            }
            return state
        }.value
    }
}
