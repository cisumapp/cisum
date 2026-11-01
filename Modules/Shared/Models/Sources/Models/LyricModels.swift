import Foundation

public enum LyricsState: Equatable {
    case idle
    case loading
    case synced
    case plain
    case unavailable(String)
}

public struct LyricSyllable: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let timestamp: TimeInterval
    public let endTime: TimeInterval
    public let isPartOfWord: Bool

    public init(text: String, timestamp: TimeInterval, endTime: TimeInterval, isPartOfWord: Bool) {
        self.text = text
        self.timestamp = timestamp
        self.endTime = endTime
        self.isPartOfWord = isPartOfWord
        self.id = "\(timestamp)-\(text)"
    }
}

public struct TimedLyricLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: TimeInterval
    public let text: String
    public let syllables: [LyricSyllable]?
    /// Backing vocals sung under the line.
    public let backgroundSyllables: [LyricSyllable]?
    /// The line in the listener's language.
    public let translation: String?
    /// The line in Latin script, for non-Latin songs.
    public let romanization: String?

    public init(
        timestamp: TimeInterval,
        text: String,
        syllables: [LyricSyllable]? = nil,
        backgroundSyllables: [LyricSyllable]? = nil,
        translation: String? = nil,
        romanization: String? = nil
    ) {
        self.timestamp = timestamp
        self.text = text
        self.syllables = syllables
        self.backgroundSyllables = backgroundSyllables
        self.translation = translation
        self.romanization = romanization
        self.id = "\(timestamp)-\(text)"
    }
}
