import Foundation
import Models
import Observation

@Observable
@MainActor
public final class LyricsController {
    public var state: LyricsState = .idle
    public var syncedLines: [TimedLyricLine] = []
    public var plainText: String?
    public var isVisible: Bool = false
    public var currentLineIndex: Int?
    public var attribution: String?

    public init() {}

    public func updateCurrentLine(for time: Double) {
        guard state == .synced else { return }
        let index = syncedLines.lastIndex { $0.timestamp <= time }
        if currentLineIndex != index {
            currentLineIndex = index
        }
    }

    public func reset() {
        state = .idle
        syncedLines = []
        plainText = nil
        currentLineIndex = nil
        attribution = nil
    }

    public func loadLyrics(synced: [TimedLyricLine], plain: String?, attribution: String?) {
        if !synced.isEmpty {
            syncedLines = synced
            state = .synced
        } else if let plain, !plain.isEmpty {
            plainText = plain
            state = .plain
        } else {
            state = .unavailable("No lyrics available for this track.")
        }
        self.attribution = attribution
    }

    public func setLoading() {
        state = .loading
    }
}
