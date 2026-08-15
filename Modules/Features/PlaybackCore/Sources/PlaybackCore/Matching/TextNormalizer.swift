//
//  TextNormalizer.swift
//  Player
//
//  THE normalizer. There were three.
//

import Foundation

/// Canonicalises titles and artist names for comparison.
///
/// The previous implementation had three of these — `SearchRanker.normalize` in ProviderSDK,
/// `YouTubeStreamResolver.normalizeForMatching` (private, in Player), and
/// `MusicMetadataNormalizer.tokenOverlapScore` (public in Utilities, used by exactly one caller).
/// They disagreed, which meant the same two strings could match in one code path and not another.
public enum TextNormalizer {
    /// Lowercased, punctuation-stripped, whitespace-collapsed, diacritics folded.
    ///
    /// Smart quotes and full-width CJK brackets are mapped to ASCII first: providers disagree on
    /// which they emit for the same release, so `"Song (Live)"` and `"Song（Live）"` must reduce to
    /// the same thing.
    public static func normalize(_ input: String) -> String {
        var text = input.lowercased()

        for (from, to) in Self.characterFolds {
            text = text.replacingOccurrences(of: from, with: to)
        }

        text = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        text = text.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return text.split(separator: " ").joined(separator: " ")
    }

    /// Normalises and removes version tags, for comparing the *work* rather than the release.
    ///
    /// `"Ivy (Remastered 2019)"` and `"Ivy"` compare equal here. Whether the difference matters is
    /// `VariantDetector`'s decision, not this one's — stripping and detecting are kept separate so
    /// a deliberate search for a live version is not defeated by the normalizer.
    public static func normalizeStrippingVersions(_ input: String) -> String {
        var text = input

        // Bracketed suffixes: (Remastered), [Live], （Live）
        text = text.replacingOccurrences(
            of: "[\\(\\[（【][^\\)\\]）】]*[\\)\\]）】]",
            with: " ",
            options: .regularExpression
        )
        // Trailing dash suffixes: "Song - 2011 Remaster"
        text = text.replacingOccurrences(
            of: "\\s+-\\s+.*$",
            with: "",
            options: .regularExpression
        )

        return normalize(text)
    }

    /// Splits into comparable tokens.
    public static func tokens(_ input: String) -> [String] {
        normalize(input).split(separator: " ").map(String.init)
    }

    /// Fraction of `expected`'s tokens present in `candidate`, 0...1.
    ///
    /// Asymmetric on purpose: a candidate carrying extra words ("Ivy — Frank Ocean — Blonde Full
    /// Album") should still match a search for "Ivy", while a candidate *missing* words should not.
    public static func tokenOverlap(expected: String, candidate: String) -> Double {
        let expectedTokens = Set(tokens(expected))
        guard !expectedTokens.isEmpty else { return 0 }
        let candidateTokens = Set(tokens(candidate))
        return Double(expectedTokens.intersection(candidateTokens).count) / Double(expectedTokens.count)
    }

    /// Sørensen–Dice similarity over character bigrams, 0...1.
    ///
    /// Catches near-misses that token overlap misses — transliterations, small misspellings, and
    /// spacing differences — because it compares character sequences rather than whole words.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let first = bigrams(normalize(a))
        let second = bigrams(normalize(b))
        guard !first.isEmpty, !second.isEmpty else {
            return normalize(a) == normalize(b) ? 1 : 0
        }
        let shared = first.intersection(second).count
        return 2.0 * Double(shared) / Double(first.count + second.count)
    }

    /// Collapses letter-spaced text: `"s l o w e d"` becomes `"slowed"`.
    ///
    /// A real pattern in user-uploaded titles that otherwise defeats tokenisation entirely, since
    /// every letter becomes its own token.
    public static func collapseSpacedLetters(_ input: String) -> String {
        input.replacingOccurrences(
            of: "\\b(?:\\w\\s){2,}\\w\\b",
            with: "",
            options: .regularExpression
        ).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - Private

    private static func bigrams(_ input: String) -> Set<String> {
        let characters = Array(input.replacingOccurrences(of: " ", with: ""))
        guard characters.count > 1 else { return [] }
        return Set((0 ..< characters.count - 1).map { String(characters[$0 ... $0 + 1]) })
    }

    /// Characters providers spell differently for the same release.
    private static let characterFolds: [(String, String)] = [
        ("\u{2018}", "'"), ("\u{2019}", "'"), // curly single quotes
        ("\u{201C}", "\""), ("\u{201D}", "\""), // curly double quotes
        ("\u{FF08}", "("), ("\u{FF09}", ")"), // full-width parentheses
        ("\u{3010}", "["), ("\u{3011}", "]"), // CJK lenticular brackets
        ("\u{2013}", "-"), ("\u{2014}", "-"), // en/em dash
        ("\u{00A0}", " "), // non-breaking space
        ("&", " and "),
    ]
}
