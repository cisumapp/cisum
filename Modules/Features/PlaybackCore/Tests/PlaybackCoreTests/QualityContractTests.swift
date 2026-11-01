//
//  QualityContractTests.swift
//  PlaybackCoreTests
//
//  Pass 1 contracts for structured quality: unknown is not zero, ranking is deterministic and
//  independent of input order, a missing field is never fabricated, and a provider's display
//  label never overrides structured evidence.
//
//  These assert the CURRENT `StreamSelector` behaviour; no production change is required.
//

import Foundation
@testable import PlaybackCore
import ProviderSDK
import Testing

@Suite("Quality contract — unknown is not zero")
struct QualityContractTests {
    private let selector = StreamSelector()

    private func stream(
        mime: String? = nil,
        bitrate: Int? = nil,
        bitDepth: Int? = nil,
        sampleRate: Int? = nil,
        kind: SourceStream.Kind = .direct,
        label: String? = nil
    ) -> SourceStream {
        SourceStream(
            url: URL(string: "https://example.com/a")!,
            kind: kind,
            mimeType: mime,
            bitrate: bitrate,
            bitDepth: bitDepth,
            sampleRate: sampleRate,
            qualityLabel: label
        )
    }

    /// Missing quality must reduce certainty, never silently become a value — so an all-unknown
    /// candidate cannot outrank a structurally-better known one, in either input order.
    @Test("an all-unknown candidate never beats a structurally-better known candidate")
    func unknownNeverBeatsKnown() throws {
        let unknown = stream()
        let known = stream(mime: "audio/flac", bitDepth: 16, sampleRate: 44100)

        #expect(try #require(selector.best(from: [unknown, known])).bitDepth == 16)
        #expect(try #require(selector.best(from: [known, unknown])).bitDepth == 16)
    }

    /// Same policy and evidence ⇒ same order, independent of adapter array order.
    @Test("ranking is deterministic and independent of input order")
    func deterministicOrder() {
        let a = stream(mime: "audio/mp4", bitrate: 128_000)
        let b = stream(mime: "audio/flac", bitDepth: 24, sampleRate: 96000)
        let c = stream(mime: "audio/mpeg", bitrate: 320_000)

        #expect(selector.best(from: [a, b, c])?.mimeType == selector.best(from: [c, b, a])?.mimeType)
        #expect(selector.best(from: [a, b, c])?.mimeType == "audio/flac")
        #expect(selector.score(a) < selector.score(b))
        #expect(selector.score(c) < selector.score(b))
    }

    /// A candidate with no metadata is still selectable; nothing is invented for it.
    @Test("an unknown-metadata candidate is selectable and never fabricated")
    func unknownIsSelectableNotFabricated() throws {
        let only = stream()
        let best = try #require(selector.best(from: [only]))

        #expect(best.bitrate == nil)
        #expect(best.bitDepth == nil)
        #expect(best.sampleRate == nil)
        #expect(selector.score(only) == 0, "no default is substituted for unknown quality")
    }

    /// The regression guard for the old MIME-string round trip: a display label is never evidence.
    @Test("a quality label never overrides structured evidence")
    func labelNeverWins() throws {
        let labeledLossy = stream(mime: "audio/mpeg", bitrate: 128_000, label: "LOSSLESS HI-RES 24-bit")
        let structurallyLossless = stream(mime: "audio/flac", bitDepth: 24, sampleRate: 96000, label: "low")

        #expect(try #require(selector.best(from: [labeledLossy, structurallyLossless])).mimeType == "audio/flac")
    }

    /// Adding known evidence can only help a candidate — it never demotes it.
    @Test("known quality is monotone: adding evidence cannot lower a candidate's rank")
    func knownIsMonotone() {
        let bare = stream(mime: "audio/mp4")
        let withBitrate = stream(mime: "audio/mp4", bitrate: 256_000)

        #expect(selector.score(withBitrate) > selector.score(bare))
    }
}
