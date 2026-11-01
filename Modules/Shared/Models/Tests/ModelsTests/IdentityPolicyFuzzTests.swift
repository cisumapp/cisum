//
//  IdentityPolicyFuzzTests.swift
//  ModelsTests
//
//  Pass 2.5 (Task A): deterministic generated-input coverage for the canonical identity policy.
//
//  The generator is a seeded SplitMix64, so any failure reproduces exactly. Each case is classified
//  by a *constructed* evidence relationship (agreeing evidence, version contradiction, bare
//  fingerprint, malformed ISRC, …), and the test asserts the documented outcome for that class —
//  rather than mirroring the policy's internal branches. Finite generated testing is not a proof;
//  the report states the actual coverage and its limits.
//

import Foundation
@testable import Models
import Testing

// MARK: - Deterministic generator

/// A seeded PRNG so every generated case — and every failure — is reproducible.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int(next() % UInt64(span))
    }

    mutating func pick<T>(_ xs: [T]) -> T {
        xs[int(in: 0 ... (xs.count - 1))]
    }

    mutating func flag() -> Bool {
        next() & 1 == 0
    }
}

// MARK: - Fixed inputs

/// Fixed seed and per-suite case count. The seed is recorded so a failure is reproducible.
private let fuzzSeed: UInt64 = 0x5EED_C0DE_1DEA_2024
private let generatedCaseCount = 200

private let plainTitles = ["Ivy", "Nikes", "Pyramids", "Hello", "Nights", "Bad Guy", "Sensitive", "Bound 2"]

/// Titles where a version tag ("live") appears as a *substring* — "Alive", "Oliver", "Deliver".
/// A substring test for version tags misclassifies these as live cuts.
private let substringTrapTitles = ["Alive", "Oliver", "Deliver", "Deliverance", "Sliver"]

private let artists = ["Frank Ocean", "Adele", "Kendrick Lamar", "Radiohead", "Billie Eilish", "FKA twigs"]
private let albums = ["Blonde", "25", "DAMN.", "In Rainbows", "When We All Fall Asleep"]
private let versionTags = ["Live", "Remix", "Acoustic", "Instrumental"]

// MARK: - Generators

/// A shape-correct ISRC: CC (letters) + XXX (alphanumeric) + YY + NNNNN (seven digits).
private func makeValidISRC(_ gen: inout SplitMix64) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let alnum = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    var s = ""
    s.append(letters[gen.int(in: 0 ... 25)])
    s.append(letters[gen.int(in: 0 ... 25)])
    for _ in 0 ..< 3 {
        s.append(alnum[gen.int(in: 0 ... (alnum.count - 1))])
    }
    for _ in 0 ..< 7 {
        s.append(Character(String(gen.int(in: 0 ... 9))))
    }
    return s
}

/// A value that resembles an ISRC but is malformed in one of several ways.
private func makeMalformedISRC(_ gen: inout SplitMix64) -> String {
    var chars = Array(makeValidISRC(&gen))
    switch gen.int(in: 0 ... 4) {
    case 0: return "" // empty
    case 1: chars.removeLast(); return String(chars) // too short
    case 2: chars.append("9"); return String(chars) // too long
    case 3: chars[11] = "X"; return String(chars) // letters in the numeric designation
    default: chars[0] = "7"; return String(chars) // digits in the country code
    }
}

// MARK: - Invariant suites

@Suite("Generated: a bare fingerprint never establishes identity")
struct FuzzBareFingerprintTests {
    /// Same normalized title and artist, but no agreeing duration — the exact class the removed
    /// `providerFingerprint` equality used to merge. Documented outcome: no merge.
    @Test("200 generated title+artist-only pairs never authorize a merge")
    func bareFingerprintNeverMerges() {
        var gen = SplitMix64(seed: fuzzSeed)
        for _ in 0 ..< generatedCaseCount {
            let title = gen.pick(plainTitles + substringTrapTitles)
            let artist = gen.pick(artists)
            let canonicalDuration = Double(gen.int(in: 120 ... 320))
            let incomingDuration: Double? = gen.flag() ? nil : canonicalDuration + Double(gen.int(in: 3 ... 45))

            let key = SongMatchKey(
                songID: "canonical",
                normalizedTitle: CanonicalSongReconciler.normalize(title),
                artistName: artist,
                durationSeconds: canonicalDuration,
                albumName: gen.flag() ? gen.pick(albums) : nil
            )
            let incoming = IncomingTrack(
                provider: .youtube,
                providerTrackID: "t",
                title: title,
                artistName: artist,
                durationSeconds: incomingDuration
            )

            let score = CanonicalSongReconciler.score(incoming, against: key)
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: nil, establishedBinding: nil, isrcMatch: nil,
                scoredMatches: [("canonical", score)]
            )
            #expect(
                evidence.songID == nil,
                "title/artist-only pair merged (title=\(title), duration=\(String(describing: incomingDuration)), score=\(score))"
            )
        }
    }
}

@Suite("Generated: agreeing evidence still merges (positive control)")
struct FuzzAgreeingEvidenceTests {
    @Test("200 generated agreeing cases reach a confident merge")
    func agreeingEvidenceMerges() {
        var gen = SplitMix64(seed: fuzzSeed &+ 1)
        for _ in 0 ..< generatedCaseCount {
            let title = gen.pick(plainTitles)
            let artist = gen.pick(artists)
            let album = gen.flag() ? gen.pick(albums) : nil
            let duration = Double(gen.int(in: 90 ... 360))

            let key = SongMatchKey(
                songID: "canonical",
                normalizedTitle: CanonicalSongReconciler.normalize(title),
                artistName: artist,
                durationSeconds: duration,
                albumName: album
            )
            let incoming = IncomingTrack(
                provider: .youtube,
                providerTrackID: "t",
                title: title,
                artistName: artist,
                albumName: album,
                durationSeconds: duration
            )

            let score = CanonicalSongReconciler.score(incoming, against: key)
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: nil, establishedBinding: nil, isrcMatch: nil,
                scoredMatches: [("canonical", score)]
            )
            #expect(
                evidence.songID == "canonical",
                "agreeing evidence failed to merge (title=\(title), score=\(score))"
            )
        }
    }
}

@Suite("Generated: version contradictions never merge")
struct FuzzVersionContradictionTests {
    @Test("200 generated version variants do not merge, including substring-trap titles")
    func versionContradictionNeverMerges() {
        var gen = SplitMix64(seed: fuzzSeed &+ 2)
        for _ in 0 ..< generatedCaseCount {
            let base = gen.pick(plainTitles + substringTrapTitles)
            let tag = gen.pick(versionTags)
            let artist = gen.pick(artists)
            let duration = Double(gen.int(in: 90 ... 360))

            let key = SongMatchKey(
                songID: "canonical",
                normalizedTitle: CanonicalSongReconciler.normalize(base),
                artistName: artist,
                durationSeconds: duration,
                albumName: nil
            )
            let incoming = IncomingTrack(
                provider: .youtube,
                providerTrackID: "t",
                title: "\(base) (\(tag))",
                artistName: artist,
                durationSeconds: duration
            )

            let score = CanonicalSongReconciler.score(incoming, against: key)
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: nil, establishedBinding: nil, isrcMatch: nil,
                scoredMatches: [("canonical", score)]
            )
            #expect(
                evidence.songID == nil,
                "\(tag) variant merged into untagged canonical (base=\(base), score=\(score))"
            )
        }
    }
}

@Suite("Generated: malformed ISRCs are never identity evidence")
struct FuzzMalformedISRCTests {
    @Test("200 generated malformed ISRCs are rejected and cannot authorize a merge")
    func malformedISRCNeverAuthorizes() {
        var gen = SplitMix64(seed: fuzzSeed &+ 3)
        for _ in 0 ..< generatedCaseCount {
            let raw = makeMalformedISRC(&gen)
            #expect(
                !CanonicalIdentityPolicy.isValidISRC(raw),
                "malformed ISRC accepted as valid: '\(raw)'"
            )
            // Given an isrcMatch candidate and no other evidence, a malformed ISRC must not merge.
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: raw, establishedBinding: nil, isrcMatch: "byISRC", scoredMatches: []
            )
            #expect(evidence.songID == nil, "malformed ISRC '\(raw)' authorized a merge")
        }
    }
}

@Suite("Generated: valid ISRC and established binding precedence")
struct FuzzPrecedenceTests {
    @Test("200 generated valid ISRC matches take precedence over scoring")
    func validISRCPrecedence() {
        var gen = SplitMix64(seed: fuzzSeed &+ 4)
        for _ in 0 ..< generatedCaseCount {
            let raw = makeValidISRC(&gen)
            #expect(CanonicalIdentityPolicy.isValidISRC(raw), "generated ISRC rejected: '\(raw)'")
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: raw, establishedBinding: nil, isrcMatch: "byISRC",
                scoredMatches: [("byScore", 0.99)]
            )
            #expect(
                evidence == .matchingISRC(songID: "byISRC"),
                "valid ISRC '\(raw)' did not resolve to matchingISRC"
            )
        }
    }

    @Test("200 generated cases: an established binding always wins")
    func establishedBindingDominates() {
        var gen = SplitMix64(seed: fuzzSeed &+ 5)
        for _ in 0 ..< generatedCaseCount {
            let raw = makeValidISRC(&gen)
            let binding = "song-\(gen.int(in: 0 ... 1000))"
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: raw, establishedBinding: binding, isrcMatch: "byISRC",
                scoredMatches: [("byScore", 0.99)]
            )
            #expect(evidence == .establishedBinding(songID: binding))
        }
    }
}

@Suite("Generated: decisions are order-independent")
struct FuzzOrderIndependenceTests {
    /// The candidate array in production comes from an unordered fetch, so the same set of
    /// candidates must yield the same decision regardless of input order — including ties.
    @Test("200 generated candidate sets produce the same decision under reordering")
    func orderIndependence() {
        var gen = SplitMix64(seed: fuzzSeed &+ 6)
        for _ in 0 ..< generatedCaseCount {
            let count = gen.int(in: 2 ... 5)
            let sharedScore = gen.flag() ? 0.95 : 0.9
            var candidates: [(songID: String, score: Double)] = []
            for index in 0 ..< count {
                let score = gen.flag() ? sharedScore : Double(gen.int(in: 0 ... 84)) / 100.0
                candidates.append((songID: "s\(index)", score: score))
            }

            let baseline = CanonicalIdentityPolicy.decide(
                isrc: nil, establishedBinding: nil, isrcMatch: nil, scoredMatches: candidates
            )
            for _ in 0 ..< 6 {
                let shuffled = candidates.shuffled(using: &gen)
                let again = CanonicalIdentityPolicy.decide(
                    isrc: nil, establishedBinding: nil, isrcMatch: nil, scoredMatches: shuffled
                )
                #expect(
                    again == baseline,
                    "decision changed under reordering: \(candidates) vs \(shuffled)"
                )
            }
        }
    }
}

@Suite("Generated: insufficient evidence stays unresolved")
struct FuzzInsufficientEvidenceTests {
    @Test("200 generated evidence-free inputs resolve to .none")
    func insufficientEvidenceResolvesToNone() {
        var gen = SplitMix64(seed: fuzzSeed &+ 7)
        for _ in 0 ..< generatedCaseCount {
            let evidence = CanonicalIdentityPolicy.decide(
                isrc: gen.flag() ? makeMalformedISRC(&gen) : nil,
                establishedBinding: nil,
                isrcMatch: gen.flag() ? "byISRC" : nil,
                scoredMatches: []
            )
            #expect(evidence == .none, "insufficient evidence produced \(evidence)")
        }
    }
}

// MARK: - Minimized permanent regressions

@Suite("Minimized identity-safety regressions (Pass 2.5)")
struct IdentitySafetyRegressionTests {
    /// A live variant of a title whose *name* contains the letters "live" as a substring must still
    /// be recognised as a different version.
    @Test("a live variant of 'Alive' must not merge into the untagged canonical")
    func substringLiveTrapDoesNotMerge() {
        let key = SongMatchKey(
            songID: "canonical",
            normalizedTitle: CanonicalSongReconciler.normalize("Alive"),
            artistName: "Radiohead",
            durationSeconds: 240,
            albumName: nil
        )
        let incoming = IncomingTrack(
            provider: .youtube,
            providerTrackID: "t",
            title: "Alive (Live)",
            artistName: "Radiohead",
            durationSeconds: 240
        )

        let score = CanonicalSongReconciler.score(incoming, against: key)
        #expect(score < CanonicalSongReconciler.confidentThreshold)
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil, establishedBinding: nil, isrcMatch: nil,
            scoredMatches: [("canonical", score)]
        )
        #expect(evidence == .none)
    }

    /// Two candidates that tie on the highest score must resolve to the same canonical song
    /// regardless of the order the fetch happened to return them in.
    @Test("equal-scoring candidates resolve deterministically")
    func equalScoreTieIsDeterministic() {
        let forward = CanonicalIdentityPolicy.decide(
            isrc: nil, establishedBinding: nil, isrcMatch: nil,
            scoredMatches: [("b", 0.95), ("a", 0.95)]
        )
        let reversed = CanonicalIdentityPolicy.decide(
            isrc: nil, establishedBinding: nil, isrcMatch: nil,
            scoredMatches: [("a", 0.95), ("b", 0.95)]
        )
        #expect(forward == reversed)
        #expect(forward == .confidentScore(songID: "a", score: 0.95))
    }
}
