//
//  IdentityPersistencePolicyTests.swift
//  ModelsTests
//
//  Pass 2: the pure canonical-identity policy (U-11) and the provider-binding persistence
//  decision (U-4), both of which `CentralMediaStore` and `SongSourceStore` now route through.
//

import Foundation
@testable import Models
import Testing

@Suite("Canonical identity policy (U-11)")
struct CanonicalIdentityPolicyTests {
    // MARK: - ISRC validation

    @Test("a well-formed ISRC is accepted, in any separator style")
    func validISRC() {
        #expect(CanonicalIdentityPolicy.isValidISRC("USUM71614169"))
        #expect(CanonicalIdentityPolicy.isValidISRC("usum71614169"))
        #expect(CanonicalIdentityPolicy.isValidISRC("US-UM7-16-14169"))
    }

    @Test("malformed or empty ISRCs are treated as absent", arguments: [
        nil, "", "   ", "NOT-AN-ISRC", "USUM7161416", "USUM716141690",
        "123456789012", "USUM7161416X",
    ] as [String?])
    func invalidISRC(raw: String?) {
        #expect(!CanonicalIdentityPolicy.isValidISRC(raw))
    }

    // MARK: - Decision ordering

    @Test("an established binding wins over ISRC and scoring")
    func establishedBindingFirst() {
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: "USUM71614169",
            establishedBinding: "song-bound",
            isrcMatch: "song-isrc",
            scoredMatches: [("song-scored", 0.95)]
        )
        #expect(evidence == .establishedBinding(songID: "song-bound"))
    }

    @Test("a valid matching ISRC merges when no binding exists")
    func matchingISRCSecond() {
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: "USUM71614169",
            establishedBinding: nil,
            isrcMatch: "song-isrc",
            scoredMatches: [("song-scored", 0.95)]
        )
        #expect(evidence == .matchingISRC(songID: "song-isrc"))
    }

    @Test("a malformed ISRC is not evidence, so scoring decides instead")
    func malformedISRCFallsThroughToScoring() {
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: "not-an-isrc",
            establishedBinding: nil,
            isrcMatch: "song-isrc",
            scoredMatches: [("song-scored", 0.95)]
        )
        #expect(evidence == .confidentScore(songID: "song-scored", score: 0.95))
    }

    @Test("a score below the confident threshold is not a merge")
    func belowThresholdDoesNotMerge() {
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil,
            establishedBinding: nil,
            isrcMatch: nil,
            scoredMatches: [("s", CanonicalSongReconciler.confidentThreshold - 0.05)]
        )
        #expect(evidence == .none)
    }

    @Test("the highest clearing score wins")
    func highestClearingScoreWins() {
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil,
            establishedBinding: nil,
            isrcMatch: nil,
            scoredMatches: [("low", 0.86), ("high", 0.95), ("alsoBelow", 0.40)]
        )
        #expect(evidence == .confidentScore(songID: "high", score: 0.95))
    }

    // MARK: - A bare fingerprint is never evidence

    @Test("equal title and artist alone never clear the threshold")
    func weakFingerprintAloneDoesNotMerge() {
        // Same normalized title and artist, but no agreed duration — the exact case the removed
        // `providerFingerprint` equality used to merge.
        let key = SongMatchKey(
            songID: "s",
            normalizedTitle: CanonicalSongReconciler.normalize("Ivy"),
            artistName: "Frank Ocean",
            durationSeconds: nil,
            albumName: nil
        )
        let score = CanonicalSongReconciler.score(
            title: "Ivy",
            artistName: "Frank Ocean",
            durationSeconds: nil,
            albumName: nil,
            against: key
        )
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil,
            establishedBinding: nil,
            isrcMatch: nil,
            scoredMatches: [("s", score)]
        )
        #expect(evidence == .none)
    }

    @Test("a version contradiction prevents a merge even with agreeing title/artist/duration")
    func versionConflictRejected() {
        let key = SongMatchKey(
            songID: "s",
            normalizedTitle: CanonicalSongReconciler.normalize("Hello"),
            artistName: "Adele",
            durationSeconds: 295,
            albumName: nil
        )
        let score = CanonicalSongReconciler.score(
            title: "Hello (Live)",
            artistName: "Adele",
            durationSeconds: 295,
            albumName: nil,
            against: key
        )
        #expect(score < CanonicalSongReconciler.confidentThreshold)
    }

    @Test("agreeing evidence still merges — the gate is not always closed")
    func agreeingEvidenceMerges() {
        let key = SongMatchKey(
            songID: "s",
            normalizedTitle: CanonicalSongReconciler.normalize("Ivy"),
            artistName: "Frank Ocean",
            durationSeconds: 249,
            albumName: nil
        )
        let score = CanonicalSongReconciler.score(
            title: "Ivy",
            artistName: "Frank Ocean",
            durationSeconds: 249,
            albumName: nil,
            against: key
        )
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil,
            establishedBinding: nil,
            isrcMatch: nil,
            scoredMatches: [("s", score)]
        )
        #expect(evidence == .confidentScore(songID: "s", score: score))
    }
}

@Suite("Provider binding persistence (U-4)")
struct ProviderBindingPolicyTests {
    @Test("an existing row is reused rather than duplicated")
    func existingRowIsReused() {
        #expect(ProviderBindingPolicy.action(existingBindingFound: true, resolvedSongID: "song") == .updateExisting)
        #expect(ProviderBindingPolicy.action(existingBindingFound: true, resolvedSongID: nil) == .updateExisting)
    }

    @Test("a known canonical song binds the new representation to it")
    func bindsWhenSongResolves() {
        #expect(
            ProviderBindingPolicy.action(existingBindingFound: false, resolvedSongID: "song")
                == .bindToSong(songID: "song")
        )
    }

    @Test("without a canonical song the binding is an orphan — no song is fabricated")
    func createsOrphanWithoutASong() {
        #expect(ProviderBindingPolicy.action(existingBindingFound: false, resolvedSongID: nil) == .createOrphan)
        #expect(ProviderBindingPolicy.action(existingBindingFound: false, resolvedSongID: "") == .createOrphan)
    }
}

@Suite("Binding evidence updates")
struct BindingEvidenceTests {
    @Test("a poorer later response never erases known evidence")
    func nilDoesNotOverwriteKnownValues() {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "t", isrc: "USUM71614169", durationSeconds: 212)

        binding.updateEvidence(isrc: nil, durationSeconds: nil, audioQualityLabel: nil, allowsStreamCaching: true)

        #expect(binding.isrc == "USUM71614169")
        #expect(binding.durationSeconds == 212)
        #expect(binding.lastVerifiedAt != nil)
    }

    @Test("a better later response does update")
    func richerResponseUpdates() {
        let binding = SongSource(sourceID: "youtube", sourceTrackID: "t")
        binding.updateEvidence(isrc: "USUM71614169", durationSeconds: 212, audioQualityLabel: "LOSSLESS", allowsStreamCaching: false)

        #expect(binding.isrc == "USUM71614169")
        #expect(binding.durationSeconds == 212)
        #expect(binding.audioQualityLabel == "LOSSLESS")
        #expect(!binding.allowsStreamCaching)
    }
}
