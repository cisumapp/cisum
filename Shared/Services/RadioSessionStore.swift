import Foundation

@MainActor
final class RadioSessionStore {
    struct CachedTrack: Codable, Sendable, Equatable {
        let videoID: String
        let title: String
        let artist: String
        let albumName: String?
        let thumbnailURLString: String?
        let isExplicit: Bool
    }

    struct Session: Codable, Sendable {
        let seedVideoID: String
        let playlistID: String?
        let continuationToken: String?
        let tracks: [CachedTrack]
        let updatedAt: Date
    }

    static let shared = RadioSessionStore()

    private enum StorageKeys {
        static let sessions = "playback.radio.sessions.bySeed"
    }

    private enum Policy {
        static let maxSessions = 64
        static let maxTracksPerSession = 200
        static let maxAge: TimeInterval = 60 * 60 * 24 * 14
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var sessionsBySeed: [String: Session] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFromDefaults()
        pruneExpiredSessions()
    }

    func session(forSeedVideoID seedVideoID: String) -> Session? {
        guard let session = sessionsBySeed[seedVideoID] else {
            return nil
        }

        if Date().timeIntervalSince(session.updatedAt) > Policy.maxAge {
            sessionsBySeed[seedVideoID] = nil
            persistToDefaults()
            return nil
        }

        return session
    }

    func save(session: Session) {
        let trimmedSeed = session.seedVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSeed.isEmpty else { return }

        let normalizedTracks = Array(session.tracks.prefix(Policy.maxTracksPerSession))
        let normalized = Session(
            seedVideoID: trimmedSeed,
            playlistID: session.playlistID,
            continuationToken: session.continuationToken,
            tracks: normalizedTracks,
            updatedAt: .now
        )

        sessionsBySeed[trimmedSeed] = normalized
        enforceSessionLimitIfNeeded()
        persistToDefaults()
    }

    func clear(seedVideoID: String) {
        sessionsBySeed[seedVideoID] = nil
        persistToDefaults()
    }

    private func loadFromDefaults() {
        guard let raw = defaults.data(forKey: StorageKeys.sessions),
              let decoded = try? decoder.decode([String: Session].self, from: raw) else {
            sessionsBySeed = [:]
            return
        }

        sessionsBySeed = decoded
    }

    private func persistToDefaults() {
        guard let encoded = try? encoder.encode(sessionsBySeed) else {
            return
        }
        defaults.set(encoded, forKey: StorageKeys.sessions)
    }

    private func pruneExpiredSessions() {
        let now = Date()
        sessionsBySeed = sessionsBySeed.filter { _, session in
            now.timeIntervalSince(session.updatedAt) <= Policy.maxAge
        }
        enforceSessionLimitIfNeeded()
        persistToDefaults()
    }

    private func enforceSessionLimitIfNeeded() {
        guard sessionsBySeed.count > Policy.maxSessions else { return }

        let sorted = sessionsBySeed.values.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        let keep = Set(sorted.prefix(Policy.maxSessions).map(\.seedVideoID))
        sessionsBySeed = sessionsBySeed.filter { keep.contains($0.key) }
    }
}
