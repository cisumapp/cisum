import Foundation
import Models

public final class QueuePersistenceStore {
    public static let lastQueueKey = "__last_active_queue__"

    private let fileManager: FileManager
    private let fileURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let directory = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
            .appendingPathComponent("Cisum", isDirectory: true)
            .appendingPathComponent("Queue", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("last_queue.json")
    }

    public func saveLastSession(state: PersistedTrackState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    public func loadLastSession() -> PersistedTrackState? {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedTrackState.self, from: data)
        else {
            return nil
        }
        return state
    }
}
