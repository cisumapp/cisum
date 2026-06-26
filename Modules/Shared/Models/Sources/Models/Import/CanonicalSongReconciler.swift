//
//  CanonicalSongReconciler.swift
//  Models
//
//  Pure, testable scoring for canonical-song reconciliation. Ported from ProviderSDK's
//  MetadataNormalizer + ReconciliationEngine.scoreMatch — scalar logic only, NO ProviderSDK
//  dependency (keeps the import layer out of the reconciliation graph, per AUDIT §C).
//  Lives in Models (the leaf) so both the Library store and the Importing layer can reach it
//  without a dependency cycle.
//

import Foundation

/// Trust ranking of providers for "which metadata is the base". Higher = more authoritative.
enum ProviderMetadataRank {
    /// ISRC-bearing, editorial providers win; video-title providers lose.
    static let order: [MediaProvider] = [
        .appleMusic, .spotify, .tidal, .qobuz, .deezer, .soundcloud, .youtubeMusic, .youtube,
    ]

    /// 0 for unranked/exotic providers, ascending for known ones.
    static func rank(_ p: MediaProvider) -> Int {
        guard let idx = order.firstIndex(of: p) else { return 0 }
        return order.count - idx
    }
}

public enum CanonicalSongReconciler {

    /// Metadata-match score at/above which an incoming track is the same canonical song.
    public static let confidentThreshold = 0.85

    // MARK: Normalization

    /// Lowercase, strip version/feat tags, drop punctuation, collapse whitespace.
    public static func normalize(_ string: String) -> String {
        var result = string.lowercased()

        // Strip parenthetical / bracketed version tags anywhere: "(2009 remaster)", "[live]", etc.
        result = result.replacingOccurrences(
            of: #"[\(\[][^\)\]]*\b(remaster|remastered|remix|live|acoustic|instrumental|explicit|clean|feat\.?|ft\.?|featuring)\b[^\)\]]*[\)\]]"#,
            with: "", options: .regularExpression)

        // Strip trailing " - remaster" / " - live" style suffixes.
        result = result.replacingOccurrences(
            of: #"\s*-\s*(remaster(ed)?|remix|live|acoustic|instrumental)\b.*$"#,
            with: "", options: .regularExpression)

        // Strip dangling "feat. ..." / "ft. ..." with no brackets.
        result = result.replacingOccurrences(
            of: #"\s+(feat\.?|ft\.?|featuring)\b.*$"#,
            with: "", options: .regularExpression)

        // Drop punctuation, collapse whitespace.
        result = result.replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Levenshtein-ratio similarity, 0.0–1.0 (ported).
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let aChars = Array(a), bChars = Array(b)
        let aLen = aChars.count, bLen = bChars.count
        if aLen == 0 { return bLen == 0 ? 1.0 : 0.0 }
        if bLen == 0 { return 0.0 }

        var prev = Array(0...bLen)
        var curr = Array(repeating: 0, count: bLen + 1)
        for i in 1...aLen {
            curr[0] = i
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        let distance = Double(prev[bLen])
        return 1.0 - distance / Double(max(aLen, bLen))
    }

    static func isSimilar(_ a: String, _ b: String, threshold: Double) -> Bool {
        let na = normalize(a), nb = normalize(b)
        return na == nb || similarity(na, nb) >= threshold
    }

    /// Coarse version-type tag of a title (so a studio cut never dedups into a live/remix cut).
    private static func versionType(_ title: String) -> String {
        let lower = title.lowercased()
        for tag in ["live", "remix", "acoustic", "instrumental"] where lower.contains(tag) {
            return tag
        }
        return "studio"
    }

    // MARK: Scoring

    /// How likely an incoming track is the same canonical song as `key`. 0.0–1.0.
    /// ISRC equality is handled by an exact fetch in the store; this is the metadata fallback.
    public static func score(_ incoming: IncomingTrack, against key: SongMatchKey) -> Double {
        // Version type must match for a confident dedup.
        if versionType(incoming.title) != versionType(key.normalizedTitle) {
            return 0.0
        }

        let titleMatch = isSimilar(incoming.title, key.normalizedTitle, threshold: 0.90)

        let durationMatch: Bool = {
            guard let a = incoming.durationSeconds, let b = key.durationSeconds else { return false }
            return abs(a - b) < 2.0
        }()

        let artistMatch: Bool = {
            guard let a = incoming.artistName, let b = key.artistName else { return false }
            return isSimilar(a, b, threshold: 0.85)
        }()

        let albumMatch: Bool = {
            guard let a = incoming.albumName, let b = key.albumName else { return false }
            return isSimilar(a, b, threshold: 0.90)
        }()

        if titleMatch, durationMatch, artistMatch {
            return albumMatch ? 0.95 : 0.85
        }
        if titleMatch, durationMatch {
            return 0.75
        }
        return 0.0
    }

    // MARK: Base provider

    /// The authoritative metadata base = higher-ranked of the current base and the incoming provider.
    public static func mergedBaseProvider(current: MediaProvider?, incoming: MediaProvider) -> MediaProvider {
        guard let current else { return incoming }
        return ProviderMetadataRank.rank(incoming) > ProviderMetadataRank.rank(current) ? incoming : current
    }
}
