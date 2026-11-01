//
//  MatchingTests.swift
//  PlayerTests
//
//  The cases the previous implementation got wrong.
//

import Foundation
import Models
@testable import PlaybackCore
import ProviderSDK
import Testing

private func track(
    _ id: String,
    _ title: String,
    _ artist: String,
    duration: Double? = nil,
    isrc: String? = nil
) -> SourceTrack {
    SourceTrack(id: id, title: title, artist: artist, durationSeconds: duration, isrc: isrc)
}

private let ivy = MatchTarget(
    title: "Ivy",
    artist: "Frank Ocean",
    album: "Blonde",
    durationSeconds: 249
)

@Suite("Matching rejects what users complain about")
struct MatchRejectionTests {
    private let matcher = SongMatcher()

    /// The single most important case. A karaoke track matches the title *perfectly*, so any
    /// title-led scoring ranks it first — which is exactly what the old resolver did.
    @Test("a karaoke version never wins over the original")
    func karaokeRejected() throws {
        let candidates = [
            track("k", "Ivy", "Karaoke Hits Band", duration: 249),
            track("o", "Ivy", "Frank Ocean", duration: 249),
        ]

        let best = try #require(matcher.best(from: candidates, for: ivy))
        #expect(best.track.id == "o")
    }

    @Test("a karaoke track alone is rejected rather than accepted as the only option")
    func karaokeAloneRejected() {
        let candidates = [track("k", "Ivy (Karaoke Version)", "Karaoke Hits Band", duration: 249)]
        #expect(matcher.best(from: candidates, for: ivy) == nil)
    }

    @Test("a cover by a different artist is rejected")
    func coverRejected() {
        let candidates = [track("c", "Ivy (Frank Ocean Cover)", "Some YouTuber", duration: 245)]
        #expect(matcher.best(from: candidates, for: ivy) == nil)
    }

    /// Real, and defeats naive tokenisation because every letter becomes its own token.
    @Test("a sped-up or letter-spaced edit does not beat the original")
    func spedUpRejected() throws {
        let candidates = [
            track("s", "Ivy (s p e d  u p)", "Frank Ocean", duration: 210),
            track("o", "Ivy", "Frank Ocean", duration: 249),
        ]

        let best = try #require(matcher.best(from: candidates, for: ivy))
        #expect(best.track.id == "o")
    }

    @Test("a live version is rejected when the original was requested")
    func liveRejected() {
        let candidates = [track("l", "Ivy (Live at Coachella)", "Frank Ocean", duration: 260)]
        #expect(matcher.best(from: candidates, for: ivy) == nil)
    }

    /// The counterpart: an explicitly requested variant must NOT be filtered out.
    @Test("a live version is accepted when the user asked for one")
    func liveAcceptedWhenRequested() throws {
        let target = MatchTarget(title: "Ivy (Live)", artist: "Frank Ocean", durationSeconds: 260)
        let candidates = [track("l", "Ivy (Live at Coachella)", "Frank Ocean", duration: 260)]

        let best = try #require(matcher.best(from: candidates, for: target))
        #expect(best.track.id == "l")
        #expect(best.variant == .live)
    }

    @Test("a remaster is acceptable — same performance, different master")
    func remasterAccepted() throws {
        let candidates = [track("r", "Ivy (2019 Remaster)", "Frank Ocean", duration: 249)]
        let best = try #require(matcher.best(from: candidates, for: ivy))
        #expect(best.track.id == "r")
    }

    /// The behaviour that made unrelated tracks play: the old resolver had a 0.20 threshold and
    /// then returned the top result anyway when nothing cleared it.
    @Test("nothing matching returns nil rather than the least-bad result")
    func noFallbackToTopResult() {
        let candidates = [
            track("x", "Completely Different Song", "Another Artist", duration: 180),
            track("y", "Also Unrelated", "Someone Else", duration: 200),
        ]
        #expect(matcher.best(from: candidates, for: ivy) == nil)
    }

    @Test("an empty candidate list returns nil")
    func emptyCandidates() {
        #expect(matcher.best(from: [], for: ivy) == nil)
    }
}

@Suite("Matching accepts what it should")
struct MatchAcceptanceTests {
    private let matcher = SongMatcher()

    /// ISRC agreement is identity, not evidence — it short-circuits scoring entirely.
    @Test("an ISRC match wins immediately, whatever the metadata says")
    func isrcWinsOutright() throws {
        let target = MatchTarget(
            title: "Ivy", artist: "Frank Ocean", durationSeconds: 249, isrc: "USUM71614169"
        )
        let candidates = [
            track("a", "Ivy", "Frank Ocean", duration: 249),
            // Metadata a scorer would hate, but the ISRC is authoritative.
            track("b", "IVY (Album Version)", "F. Ocean", duration: 250, isrc: "USUM71614169"),
        ]

        let best = try #require(matcher.best(from: candidates, for: target))
        #expect(best.track.id == "b")
        #expect(best.isExact)
        #expect(best.score == 1)
    }

    @Test("duration agreement breaks a tie between equal metadata")
    func durationBreaksTies() throws {
        let candidates = [
            track("short", "Ivy", "Frank Ocean", duration: 180),
            track("right", "Ivy", "Frank Ocean", duration: 249),
        ]

        let best = try #require(matcher.best(from: candidates, for: ivy))
        #expect(best.track.id == "right")
    }

    @Test("a missing duration neither helps nor hurts")
    func missingDurationTolerated() throws {
        let candidates = [track("n", "Ivy", "Frank Ocean")]
        let best = try #require(matcher.best(from: candidates, for: ivy))
        #expect(best.track.id == "n")
    }

    @Test("punctuation and case differences do not prevent a match")
    func punctuationTolerated() throws {
        let target = MatchTarget(title: "Don't Stop Me Now", artist: "Queen", durationSeconds: 209)
        let candidates = [track("q", "Dont Stop Me Now", "QUEEN", duration: 209)]

        let best = try #require(matcher.best(from: candidates, for: target))
        #expect(best.track.id == "q")
    }

    /// Providers disagree on which bracket forms they emit for the same release.
    @Test("full-width CJK brackets fold to ASCII")
    func fullWidthBracketsFold() {
        #expect(
            TextNormalizer.normalizeStrippingVersions("Song（Live）")
                == TextNormalizer.normalizeStrippingVersions("Song (Live)")
        )
    }
}

@Suite("Query ladder")
struct QueryLadderTests {
    /// Retrying matters because provider catalogues disagree on how a release is indexed; a
    /// single query shape fails for a whole category of music.
    @Test("attempts get progressively looser")
    func laddersLooser() {
        let queries = SongMatcher().queries(for: ivy)
        #expect(queries.count >= 2)
        #expect(queries[0] == "Ivy Frank Ocean")
        #expect(queries.contains("Ivy"))
    }

    @Test("a versioned title adds a version-stripped attempt")
    func versionStrippedAttempt() {
        let target = MatchTarget(title: "Ivy (2019 Remaster)", artist: "Frank Ocean")
        let queries = SongMatcher().queries(for: target)
        #expect(queries.contains { $0.hasPrefix("ivy ") && !$0.contains("remaster") })
    }
}

@Suite("Variant detection")
struct VariantDetectionTests {
    @Test("plain titles are detected as original")
    func originalDetected() {
        #expect(VariantDetector.primary(in: "Ivy") == .original)
        #expect(VariantDetector.primary(in: "Ivy - Frank Ocean") == .original)
    }

    @Test("variants are detected", arguments: [
        ("Ivy (Live at Coachella)", RecordingVariant.live),
        ("Ivy (Karaoke Version)", .karaoke),
        ("Ivy (Acoustic)", .acoustic),
        ("Ivy (Instrumental)", .instrumental),
        ("Ivy (Kaytranada Remix)", .remix),
        ("Ivy (2019 Remaster)", .remastered),
        ("Ivy [Nightcore]", .nightcore),
    ])
    func variantsDetected(title: String, expected: RecordingVariant) {
        #expect(VariantDetector.primary(in: title) == expected)
    }

    /// A "Live (Karaoke Version)" is a karaoke track first and foremost.
    @Test("the most disqualifying variant wins when several are present")
    func mostDisqualifyingWins() {
        #expect(VariantDetector.primary(in: "Ivy (Live) (Karaoke Version)") == .karaoke)
    }

    @Test("a remaster is the same performance; a live take is not")
    func performanceClassification() {
        #expect(!RecordingVariant.remastered.isDifferentPerformance)
        #expect(!RecordingVariant.radioEdit.isDifferentPerformance)
        #expect(RecordingVariant.live.isDifferentPerformance)
        #expect(RecordingVariant.karaoke.isDifferentPerformance)
    }
}

@Suite("Stream selection uses structured fields, never strings")
struct StreamSelectionTests {
    private let selector = StreamSelector()

    private func stream(
        _ mime: String?, bitrate: Int? = nil, bitDepth: Int? = nil,
        sampleRate: Int? = nil, kind: SourceStream.Kind = .direct,
        label: String? = nil
    ) -> SourceStream {
        SourceStream(
            url: URL(string: "https://example.com/a")!,
            kind: kind, mimeType: mime, bitrate: bitrate,
            bitDepth: bitDepth, sampleRate: sampleRate, qualityLabel: label
        )
    }

    @Test("lossless beats lossy")
    func losslessWins() throws {
        let best = try #require(selector.best(from: [
            stream("audio/mp4", bitrate: 256_000),
            stream("audio/flac", bitDepth: 16, sampleRate: 44100),
        ]))
        #expect(best.mimeType == "audio/flac")
    }

    @Test("hi-res beats CD-quality lossless")
    func hiResWins() throws {
        let best = try #require(selector.best(from: [
            stream("audio/flac", bitDepth: 16, sampleRate: 44100),
            stream("audio/flac", bitDepth: 24, sampleRate: 96000),
        ]))
        #expect(best.bitDepth == 24)
    }

    @Test("higher bitrate wins among equal codecs")
    func bitrateWins() throws {
        let best = try #require(selector.best(from: [
            stream("audio/mp4", bitrate: 128_000),
            stream("audio/mp4", bitrate: 256_000),
        ]))
        #expect(best.bitrate == 256_000)
    }

    /// The regression guard for the old MIME-string round trip: a stream that merely *claims*
    /// lossless in its display label must not beat one whose structured fields say otherwise.
    @Test("the provider's quality label is ignored entirely")
    func labelIgnored() throws {
        let best = try #require(selector.best(from: [
            stream("audio/mpeg", bitrate: 128_000, label: "LOSSLESS HI-RES 24-bit"),
            stream("audio/flac", bitDepth: 24, sampleRate: 96000, label: "low"),
        ]))
        #expect(best.mimeType == "audio/flac")
    }

    @Test("a progressive file beats an HLS manifest, all else equal")
    func directBeatsHLS() throws {
        let best = try #require(selector.best(from: [
            stream("audio/mp4", bitrate: 256_000, kind: .hls),
            stream("audio/mp4", bitrate: 256_000, kind: .direct),
        ]))
        #expect(best.kind == .direct)
    }

    @Test("an empty list yields nothing")
    func emptyStreams() {
        #expect(selector.best(from: []) == nil)
    }
}

@Suite("Matching prefers the official audio")
struct OfficialAudioTests {
    private let matcher = SongMatcher()

    private func kind(_ id: String, _ title: String, _ kind: RecordingKind?) -> SourceTrack {
        SourceTrack(id: id, title: title, artist: "Frank Ocean", durationSeconds: 249, recordingKind: kind)
    }

    /// The reported bug: the music video's edit played instead of the album track.
    @Test("official audio beats a music video of the same song")
    func audioBeatsVideo() throws {
        let best = try #require(matcher.best(from: [
            kind("v", "Ivy", .musicVideo),
            kind("a", "Ivy", .officialAudio),
        ], for: ivy))
        #expect(best.track.id == "a")
    }

    @Test("official audio wins even when the video's title scores higher")
    func audioBeatsBetterScoringVideo() throws {
        let best = try #require(matcher.best(from: [
            kind("v", "Ivy", .musicVideo),
            kind("a", "Ivy - Album Version", .officialAudio),
        ], for: ivy))
        #expect(best.track.id == "a")
    }

    @Test("a user upload is rejected even as the only exact-looking result")
    func userUploadRejected() {
        #expect(matcher.best(from: [kind("u", "Ivy", .userUpload)], for: ivy) == nil)
    }

    @Test("a music video is still accepted when nothing better exists")
    func videoAsLastResort() throws {
        let best = try #require(matcher.best(from: [kind("v", "Ivy", .musicVideo)], for: ivy))
        #expect(best.track.id == "v")
    }

    @Test("an unlabelled catalogue track beats a music video")
    func unlabelledBeatsVideo() throws {
        let best = try #require(matcher.best(from: [
            kind("v", "Ivy", .musicVideo),
            kind("c", "Ivy", nil),
        ], for: ivy))
        #expect(best.track.id == "c")
    }

    @Test("a matched music video carries no identity confirmation into ranking")
    @MainActor
    func videoMatchIsUnconfirmed() throws {
        let video = try #require(matcher.best(from: [kind("v", "Ivy", .musicVideo)], for: ivy))
        let audio = try #require(matcher.best(from: [kind("a", "Ivy", .officialAudio)], for: ivy))
        #expect(PlaybackResolver.searchIdentity(for: video) == .unconfirmed)
        #expect(PlaybackResolver.searchIdentity(for: audio) == .confirmed(.confidentMatch))
    }
}

@Suite("Matching accepts only official videos")
struct OfficialVideoTests {
    private let matcher = SongMatcher()
    private let blindingLights = MatchTarget(title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

    private func video(_ id: String, _ title: String, by channel: String) -> SourceTrack {
        SourceTrack(id: id, title: title, artist: channel, durationSeconds: 200, recordingKind: .musicVideo)
    }

    /// The reported case: a talk-show upload of the right song, whose channel shares only "The".
    @Test("a talk-show performance is not an official video")
    func talkShowRejected() {
        let lateShow = video("l", "The Weeknd: \"Blinding Lights\"", by: "The Late Show with Stephen Colbert")
        #expect(matcher.best(from: [lateShow], for: blindingLights) == nil)
    }

    @Test("a filler word alone never clears the artist gate")
    func fillerWordIgnored() {
        #expect(TextNormalizer.nameOverlap(expected: "The Weeknd", candidate: "The Late Show") == 0)
        #expect(TextNormalizer.nameOverlap(expected: "The The", candidate: "The The") == 1)
    }

    @Test("a video from the artist's own channel is accepted")
    func artistChannelAccepted() throws {
        let official = video("o", "The Weeknd - Blinding Lights (Official Video)", by: "The Weeknd")
        #expect(try #require(matcher.best(from: [official], for: blindingLights)).track.id == "o")
        // A VEVO channel arrives with the suffix stripped by the YouTube adapter.
        let vevo = video("v", "The Weeknd - Blinding Lights (Official Video)", by: "TheWeeknd")
        #expect(try #require(matcher.best(from: [vevo], for: blindingLights)).track.id == "v")
    }

    @Test("a fan channel named after the artist is not official")
    func fanChannelRejected() {
        let fan = video("f", "Blinding Lights", by: "The Weeknd Fan Edits Daily")
        #expect(matcher.best(from: [fan], for: blindingLights) == nil)
    }
}
