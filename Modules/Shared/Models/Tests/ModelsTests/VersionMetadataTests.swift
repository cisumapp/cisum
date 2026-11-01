//
//  VersionMetadataTests.swift
//  ModelsTests
//
//  Pass 2.6: structured recording-version identity. Covers the classifier, the provenance-aware
//  evidence type, the conflict/merge policy, and the reconciliation gate that now consumes them.
//

import Foundation
@testable import Models
import Testing

// MARK: - Classification

@Suite("Version classification")
struct VersionClassificationTests {
    @Test("title markers classify into the right version", arguments: [
        ("Ivy", RecordingVersion.original),
        ("Ivy (Live)", .live),
        ("Ivy - Live", .live),
        ("Ivy [Live at Coachella]", .live),
        ("Ivy (Remix)", .remix),
        ("Ivy (Acoustic)", .acoustic),
        ("Ivy (Instrumental)", .instrumental),
        ("Ivy (2019 Remaster)", .remaster),
        ("Ivy (Remastered)", .remaster),
        ("Pyramids (Studio Version)", .original),
    ])
    func classifiesCategories(title: String, expected: RecordingVersion) {
        #expect(VersionClassifier.infer(from: title) == expected)
    }

    /// A word that merely *contains* a marker must not be read as one.
    @Test("substring traps are not mistaken for a live cut", arguments: [
        "Alive", "Oliver", "Deliver", "Deliverance", "Sliver", "Believe", "Sensitive",
    ])
    func substringTrapsAreOriginal(title: String) {
        #expect(VersionClassifier.infer(from: title) == .original)
    }

    @Test("a remaster is the same performance as the original; a live take is not")
    func compatibilityRules() {
        #expect(RecordingVersion.remaster.isCompatible(with: .original))
        #expect(RecordingVersion.original.isCompatible(with: .original))
        #expect(!RecordingVersion.live.isCompatible(with: .original))
        #expect(!RecordingVersion.original.isCompatible(with: .remix))
        // Unknown carries no constraint.
        #expect(RecordingVersion.unknown.isCompatible(with: .live))
        #expect(RecordingVersion.unknown.isCompatible(with: .unknown))
    }
}

// MARK: - Provenance

@Suite("Version evidence provenance")
struct VersionEvidenceTests {
    @Test("reported evidence carries its source and is distinguishable from inference")
    func reportedCarriesProvenance() {
        let reported = VersionEvidence.reported(.live, sourceID: "spotify")
        #expect(reported.isReported)
        #expect(reported.version == .live)
        #expect(reported.sourceID == "spotify")

        let inferred = VersionEvidence.inferred(.live)
        #expect(!inferred.isReported)
        #expect(inferred.sourceID == nil)
        #expect(inferred.version == .live)

        #expect(VersionEvidence.unknown.version == .unknown)
        #expect(!VersionEvidence.unknown.isReported)
    }

    @Test("a title-only inference never becomes reported evidence")
    func inferenceIsNotReported() {
        // Building evidence from a title produces inferred, never reported.
        let fromTitle = VersionEvidence.inferred(VersionClassifier.infer(from: "Ivy (Live)"))
        #expect(!fromTitle.isReported)
        #expect(fromTitle.version == .live)
    }
}

// MARK: - Conflict and merge policy

@Suite("Version evidence conflict policy")
struct VersionEvidencePolicyTests {
    @Test("unknown never overwrites known evidence, in either direction")
    func unknownNeverOverwritesKnown() {
        let known = VersionEvidence.reported(.live, sourceID: "a")
        #expect(VersionEvidencePolicy.merged(existing: known, incoming: .unknown) == known)
        #expect(VersionEvidencePolicy.merged(existing: .unknown, incoming: known) == known)

        let inferred = VersionEvidence.inferred(.acoustic)
        #expect(VersionEvidencePolicy.merged(existing: inferred, incoming: .unknown) == inferred)
        #expect(VersionEvidencePolicy.merged(existing: .unknown, incoming: inferred) == inferred)
    }

    @Test("reported evidence outranks inferred evidence")
    func reportedOutranksInferred() {
        let reported = VersionEvidence.reported(.remix, sourceID: "tidal")
        #expect(VersionEvidencePolicy.merged(existing: .inferred(.live), incoming: reported) == reported)
        #expect(VersionEvidencePolicy.merged(existing: reported, incoming: .inferred(.live)) == reported)
        // Unknown incoming against inferred existing keeps the inference.
        #expect(VersionEvidencePolicy.merged(existing: .inferred(.live), incoming: .unknown) == .inferred(.live))
    }

    @Test("disagreeing reported sources resolve deterministically to the first established value")
    func sourceDisagreementIsDeterministic() {
        let existing = VersionEvidence.reported(.live, sourceID: "spotify")
        let conflicting = VersionEvidence.reported(.remix, sourceID: "tidal")
        #expect(VersionEvidencePolicy.merged(existing: existing, incoming: conflicting) == existing)
        // And the symmetric call is stable too — no flip-flop.
        #expect(VersionEvidencePolicy.merged(existing: conflicting, incoming: existing) == conflicting)
    }

    @Test("resolution prefers reported, then inferred, then falls back to the raw title")
    func resolutionOrder() {
        #expect(VersionEvidencePolicy.resolvedVersion(.reported(.instrumental, sourceID: "x"), rawTitle: "Ivy (Live)") == .instrumental)
        #expect(VersionEvidencePolicy.resolvedVersion(.inferred(.live), rawTitle: "Ivy") == .live)
        #expect(VersionEvidencePolicy.resolvedVersion(.unknown, rawTitle: "Ivy (Remix)") == .remix)
        #expect(VersionEvidencePolicy.resolvedVersion(nil, rawTitle: "Ivy (2019 Remaster)") == .remaster)
    }
}

// MARK: - Reconciliation gate

@Suite("Version-aware reconciliation gate")
struct VersionAwareReconciliationTests {
    private func key(
        title: String,
        artist: String = "Frank Ocean",
        duration: Double = 249,
        evidence: VersionEvidence? = nil
    ) -> SongMatchKey {
        SongMatchKey(
            songID: "canonical",
            normalizedTitle: CanonicalSongReconciler.normalize(title),
            artistName: artist,
            durationSeconds: duration,
            albumName: nil,
            title: title,
            versionEvidence: evidence
        )
    }

    /// Regression guard: the ordinary agreeing case still merges.
    @Test("agreeing plain evidence still clears the threshold")
    func agreeingStillMerges() {
        let score = CanonicalSongReconciler.score(
            title: "Ivy", artistName: "Frank Ocean", durationSeconds: 249, albumName: nil,
            against: key(title: "Ivy")
        )
        #expect(score >= CanonicalSongReconciler.confidentThreshold)
    }

    @Test("an explicit version contradiction blocks a merge even with agreeing title/artist/duration")
    func explicitContradictionBlocks() {
        let original = key(title: "Ivy")
        let live = IncomingTrack(
            provider: .spotify, providerTrackID: "t",
            title: "Ivy", artistName: "Frank Ocean", durationSeconds: 249,
            version: .reported(.live, sourceID: "spotify")
        )
        #expect(CanonicalSongReconciler.score(live, against: original) == 0.0)
    }

    @Test("explicit version agreement permits the merge")
    func explicitAgreementMerges() {
        let canonical = key(title: "Ivy (Live)", evidence: .reported(.live, sourceID: "youtube_music"))
        let incoming = IncomingTrack(
            provider: .spotify, providerTrackID: "t",
            title: "Ivy (Live)", artistName: "Frank Ocean", durationSeconds: 249,
            version: .reported(.live, sourceID: "spotify")
        )
        #expect(CanonicalSongReconciler.score(incoming, against: canonical) >= CanonicalSongReconciler.confidentThreshold)
    }

    /// Structured evidence must be trusted over a misleading title.
    @Test("reported evidence overrides a misleading title marker")
    func reportedEvidenceOverridesTitle() {
        let canonical = key(title: "Ivy")
        // Title says live, but the source reports the studio original.
        let incoming = IncomingTrack(
            provider: .spotify, providerTrackID: "t",
            title: "Ivy (Live)", artistName: "Frank Ocean", durationSeconds: 249,
            version: .reported(.original, sourceID: "spotify")
        )
        #expect(CanonicalSongReconciler.score(incoming, against: canonical) >= CanonicalSongReconciler.confidentThreshold)
    }

    @Test("an unknown incoming version falls back to title inference")
    func unknownFallsBackToTitle() {
        let canonical = key(title: "Ivy")
        let liveLooking = IncomingTrack(
            provider: .youtube, providerTrackID: "t",
            title: "Ivy (Live)", artistName: "Frank Ocean", durationSeconds: 249
        )
        #expect(CanonicalSongReconciler.score(liveLooking, against: canonical) == 0.0)
    }

    @Test("a versioned canonical title is compared against the incoming version, not treated as studio")
    func canonicalTitleMarkerIsRespected() {
        // A live canonical record must not absorb a plain studio take…
        let liveCanonical = key(title: "Ivy (Live)")
        let studio = IncomingTrack(
            provider: .youtube, providerTrackID: "t",
            title: "Ivy", artistName: "Frank Ocean", durationSeconds: 249
        )
        #expect(CanonicalSongReconciler.score(studio, against: liveCanonical) == 0.0)

        // …but the live take matching its own live canonical does merge.
        let liveIncoming = IncomingTrack(
            provider: .youtube, providerTrackID: "t",
            title: "Ivy (Live)", artistName: "Frank Ocean", durationSeconds: 249
        )
        #expect(CanonicalSongReconciler.score(liveIncoming, against: liveCanonical) >= CanonicalSongReconciler.confidentThreshold)
    }

    @Test("a remaster still merges with the original recording")
    func remasterMergesWithOriginal() {
        let canonical = key(title: "Ivy")
        let remaster = IncomingTrack(
            provider: .appleMusic, providerTrackID: "t",
            title: "Ivy (2019 Remaster)", artistName: "Frank Ocean", durationSeconds: 249
        )
        #expect(CanonicalSongReconciler.score(remaster, against: canonical) >= CanonicalSongReconciler.confidentThreshold)
    }

    /// The decision over a set of candidates must not depend on the order they arrive in.
    @Test("version-aware candidate selection is order-independent")
    func orderIndependent() {
        let candidates: [(songID: String, score: Double)] = [
            ("live", 0.95), ("studio", 0.95), ("other", 0.80),
        ]
        let forward = CanonicalIdentityPolicy.decide(
            isrc: nil, establishedBinding: nil, isrcMatch: nil, scoredMatches: candidates
        )
        let reversed = CanonicalIdentityPolicy.decide(
            isrc: nil, establishedBinding: nil, isrcMatch: nil, scoredMatches: Array(candidates.reversed())
        )
        #expect(forward == reversed)
    }
}
