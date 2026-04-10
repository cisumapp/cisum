import Foundation
import YouTubeSDK

@MainActor
final class SearchResultsCache {
    static let shared = SearchResultsCache()

    struct Lookup<Value> {
        let results: [Value]
        let isStale: Bool
    }

    struct MusicEntry {
        let results: [YouTubeMusicSong]
        let cachedAt: Date
    }

    struct VideoEntry {
        let results: [YouTubeSearchResult]
        let cachedAt: Date
    }

    private var musicStore: [String: MusicEntry] = [:]
    private var videoStore: [String: VideoEntry] = [:]
    private let musicLRU = LRUList<String>()
    private let videoLRU = LRUList<String>()
    private let musicMax: Int = 50
    private let videoMax: Int = 50
    private let ttl: TimeInterval = 300 // 5 minutes

    init() {}

    func getMusicResults(for query: String) -> Lookup<YouTubeMusicSong>? {
        let key = normalized(query)
        guard let entry = musicStore[key] else { return nil }
        touchMusic(key)
        return Lookup(results: entry.results, isStale: Date().timeIntervalSince(entry.cachedAt) > ttl)
    }

    func setMusicResults(_ results: [YouTubeMusicSong], for query: String) {
        let key = normalized(query)
        musicStore[key] = MusicEntry(results: results, cachedAt: Date())
        touchMusic(key)
        evictMusicIfNeeded()
    }

    func getVideoResults(for query: String) -> Lookup<YouTubeSearchResult>? {
        let key = normalized(query)
        guard let entry = videoStore[key] else { return nil }
        touchVideo(key)
        return Lookup(results: entry.results, isStale: Date().timeIntervalSince(entry.cachedAt) > ttl)
    }

    func setVideoResults(_ results: [YouTubeSearchResult], for query: String) {
        let key = normalized(query)
        videoStore[key] = VideoEntry(results: results, cachedAt: Date())
        touchVideo(key)
        evictVideoIfNeeded()
    }

    func clear() {
        musicStore.removeAll()
        videoStore.removeAll()
        musicLRU.removeAll()
        videoLRU.removeAll()
    }

    private func touchMusic(_ q: String) {
        musicLRU.touch(q)
    }

    private func touchVideo(_ q: String) {
        videoLRU.touch(q)
    }

    private func evictMusicIfNeeded() {
        while musicLRU.count > musicMax, let staleKey = musicLRU.removeLast() {
            musicStore[staleKey] = nil
        }
    }

    private func evictVideoIfNeeded() {
        while videoLRU.count > videoMax, let staleKey = videoLRU.removeLast() {
            videoStore[staleKey] = nil
        }
    }

    private func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
