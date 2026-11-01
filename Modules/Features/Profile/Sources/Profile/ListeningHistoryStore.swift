import Foundation
import Models
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

    /// Records one finished play of `ref` — the recording that actually played.
    public func recordPlay(_ ref: PlayableRef, startedAt: Date, listenedSeconds: Double) {
        let entry = ListeningHistoryEntry(
            mediaID: ref.sourceTrackID,
            title: ref.title,
            artist: ref.artist,
            album: ref.album,
            artworkURL: ref.artworkURL?.absoluteString,
            streamingService: ref.sourceID,
            startedAt: startedAt
        )
        entry.endedAt = .now
        entry.listenedSeconds = max(listenedSeconds, 0)
        modelContext.insert(entry)
        try? modelContext.save()
    }

    /// Tracks the user actually listened to, most recent first, one per recording.
    ///
    /// `minimumSeconds` keeps quick skips out: a track abandoned after five seconds says little
    /// about taste.
    public func recentPlays(limit: Int = 200, minimumSeconds: Double = 30) -> [PlayableRef] {
        var descriptor = FetchDescriptor<ListeningHistoryEntry>(
            predicate: #Predicate { $0.listenedSeconds >= minimumSeconds },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        var seen = Set<String>()
        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap { entry in
            guard seen.insert("\(entry.streamingService):\(entry.mediaID)").inserted else { return nil }
            return PlayableRef(
                songID: nil,
                sourceID: entry.streamingService,
                sourceTrackID: entry.mediaID,
                title: entry.title,
                artist: entry.artist,
                artworkURL: entry.artworkURL.flatMap(URL.init(string:)),
                album: entry.album
            )
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
