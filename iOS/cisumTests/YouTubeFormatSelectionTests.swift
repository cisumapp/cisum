//
//  YouTubeFormatSelectionTests.swift
//  cisumTests
//
//  The YouTube adapter's format decision: which parsed formats become playback candidates, in what
//  order, and with which User-Agent.
//
//  These drive `YouTubeFormatSelection` directly rather than through `YouTubeMusicSource.streamCandidates`,
//  because the part worth testing is the decision, not the network call that feeds it. `InternalVideoFormat`
//  is constructed here from synthetic values; nothing in this file contacts YouTube, and no number in it
//  is a measurement of a real stream.
//

@testable import Core
import XCTest
import YouTubeSDK

/// `@MainActor` because the app builds its modules with main-actor-by-default isolation, so the
/// types this drives are main-actor isolated.
@MainActor
final class YouTubeFormatSelectionTests: XCTestCase {
    private func format(
        itag: Int,
        mimeType: String,
        url: String? = "https://cdn.example.com/format",
        bitrate: Int? = nil
    ) -> InternalVideoFormat {
        InternalVideoFormat(
            itag: itag,
            label: "240p",
            width: 0,
            height: 0,
            fps: 30,
            mimeType: mimeType,
            url: url.flatMap(URL.init(string:)),
            bitrate: bitrate
        )
    }

    // MARK: - Compatibility

    func testAudioOnlyAACFormatsAreCandidates() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 140, mimeType: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 128_000)],
            expiry: nil
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.mimeType, "audio/mp4; codecs=\"mp4a.40.2\"")
        XCTAssertEqual(candidates.first?.bitrate, 128_000)
        XCTAssertEqual(candidates.first?.kind, .direct)
    }

    /// YouTube offers Opus in WebM as adaptive audio. AVPlayer cannot play it and cisum has no
    /// transcoder, so it must never reach the player — and the refusal must be deliberate.
    func testOpusInWebMIsNotACandidate() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 251, mimeType: "audio/webm; codecs=\"opus\"", bitrate: 160_000),
                format(itag: 140, mimeType: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 128_000),
            ],
            expiry: nil
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.bitrate, 128_000)
    }

    /// A video-only format parses and has a URL; playing it would be silent.
    func testVideoOnlyFormatsAreNotCandidates() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 137, mimeType: "video/mp4; codecs=\"avc1.640028\"", bitrate: 4_000_000),
                format(itag: 140, mimeType: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 128_000),
            ],
            expiry: nil
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.bitrate, 128_000)
    }

    func testMuxedFormatIsACandidateAndCarriesNoBitrate() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 18, mimeType: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"", bitrate: 1_500_000)],
            expiry: nil
        )

        XCTAssertEqual(candidates.count, 1)
        // The container is what tells the ranker it carries video...
        XCTAssertEqual(candidates.first?.mimeType, "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"")
        // ...and a video-inclusive bitrate must not be offered as audio-quality evidence.
        XCTAssertNil(candidates.first?.bitrate)
    }

    func testFormatWithoutURLIsNotACandidate() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 140, mimeType: "audio/mp4", url: nil, bitrate: 128_000)],
            expiry: nil
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Ordering and de-duplication

    func testAudioOnlyFormatsAreOrderedBestBitrateFirst() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 139, mimeType: "audio/mp4", url: "https://cdn.example.com/low", bitrate: 48000),
                format(itag: 140, mimeType: "audio/mp4", url: "https://cdn.example.com/high", bitrate: 128_000),
            ],
            expiry: nil
        )

        XCTAssertEqual(candidates.map(\.bitrate), [128_000, 48000])
        XCTAssertEqual(candidates.first?.url.lastPathComponent, "high")
    }

    /// A repeated itag/mimeType pair is one format, however many clients reported it.
    func testDuplicateFormatIsCollapsed() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 140, mimeType: "audio/mp4", url: "https://cdn.example.com/a", bitrate: 128_000),
                format(itag: 140, mimeType: "audio/mp4", url: "https://cdn.example.com/b", bitrate: 128_000),
            ],
            expiry: nil
        )

        XCTAssertEqual(candidates.count, 1)
    }

    func testMuxedCandidatesFollowAudioOnlyOnes() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 18, mimeType: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"", url: "https://cdn.example.com/muxed"),
                format(itag: 140, mimeType: "audio/mp4", url: "https://cdn.example.com/audio", bitrate: 128_000),
            ],
            expiry: nil
        )

        XCTAssertEqual(candidates.map(\.url.lastPathComponent), ["audio", "muxed"])
    }

    /// A reported `0` is not a bitrate. Unknown must stay unknown.
    func testZeroBitrateIsTreatedAsUnreported() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 140, mimeType: "audio/mp4", bitrate: 0)],
            expiry: nil
        )

        XCTAssertNil(candidates.first?.bitrate)
    }

    // MARK: - Manifest

    func testManifestIsAnAdaptiveCandidate() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: URL(string: "https://manifest.googlevideo.com/api/manifest/hls_variant/x"),
            formats: [],
            expiry: nil
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.kind, .hls)
    }

    // MARK: - Headers

    /// The CDN checks the User-Agent the URL was signed for, and a mismatch is refused (403). The
    /// signing client is named in the URL's `c=`, so that — not the format's kind — picks the agent.
    func testEachCandidateCarriesTheUserAgentOfItsSigningClient() {
        let candidates = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [
                format(itag: 140, mimeType: "audio/mp4", url: "https://cdn.example.com/audio?c=VISIONOS", bitrate: 128_000),
                format(itag: 18, mimeType: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"", url: "https://cdn.example.com/muxed?c=ANDROID"),
            ],
            expiry: nil
        )

        let agent = { (path: String) in candidates.first { $0.url.lastPathComponent == path }?.headers["User-Agent"] }
        XCTAssertEqual(agent("audio"), InnerTubeClients.VisionOS.userAgent)
        XCTAssertEqual(agent("muxed"), InnerTubeClients.Android.userAgent)
    }

    // MARK: - Expiry

    func testExpiryIsCarriedThroughAndUnknownStaysUnknown() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let dated = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 140, mimeType: "audio/mp4", bitrate: 128_000)],
            expiry: expiry
        )
        XCTAssertEqual(dated.first?.expiresAt, expiry)

        let undated = YouTubeFormatSelection.candidates(
            hlsURL: nil,
            formats: [format(itag: 140, mimeType: "audio/mp4", bitrate: 128_000)],
            expiry: nil
        )
        XCTAssertNil(undated.first?.expiresAt)
    }

    func testEmptyInputProducesNoCandidates() {
        XCTAssertTrue(YouTubeFormatSelection.candidates(hlsURL: nil, formats: [], expiry: nil).isEmpty)
    }
}
