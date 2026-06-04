import Foundation
import Models
import Profile
import SwiftData

@ModelActor
public actor ListeningHistoryStore {
    public func startSession(
        mediaID: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        streamingService: String,
        startedAt: Date = .now
    ) -> PersistentIdentifier {
        let entry = ListeningHistoryEntry(
            mediaID: mediaID,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL?.absoluteString,
            streamingService: streamingService,
            startedAt: startedAt
        )
        modelContext.insert(entry)
        try? modelContext.save()
        return entry.persistentModelID
    }

    public func finishSession(
        id: PersistentIdentifier,
        endedAt: Date = .now,
        listenedSeconds: Double,
        wasScrobbled: Bool,
        scrobbledAt: Date? = nil
    ) {
        if let entry = modelContext.model(for: id) as? ListeningHistoryEntry {
            entry.endedAt = endedAt
            entry.listenedSeconds = max(listenedSeconds, 0)
            entry.wasScrobbled = wasScrobbled
            entry.scrobbledAt = scrobbledAt
            try? modelContext.save()
        }
    }

    public func markScrobbled(id: PersistentIdentifier, scrobbledAt: Date = .now) {
        if let entry = modelContext.model(for: id) as? ListeningHistoryEntry {
            entry.wasScrobbled = true
            entry.scrobbledAt = scrobbledAt
            try? modelContext.save()
        }
    }
}

public extension ListeningHistoryStore {
    static var preview: ListeningHistoryStore {
        let container = try! ModelContainer(
            for: Schema([ListeningHistoryEntry.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ListeningHistoryStore(modelContainer: container)
    }
}
