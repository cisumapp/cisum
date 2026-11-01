//
//  FormatCompatibilityTests.swift
//  PlaybackCoreTests
//
//  Which parsed provider formats may be handed to AVPlayer, and the reason when they may not.
//

import AVFoundation
import Foundation
@testable import PlaybackCore
import ProviderSDK
import Testing

@Suite("AVPlayer format compatibility")
struct FormatCompatibilityTests {
    @Test("audio-only AAC in MP4 is playable")
    func audioOnlyAACIsPlayable() {
        #expect(
            PlaybackFormatCompatibility.assess(mimeType: "audio/mp4; codecs=\"mp4a.40.2\"", kind: .direct)
                == .playable(.progressiveAudio)
        )
        #expect(PlaybackFormatCompatibility.assess(mimeType: "audio/mp4", kind: .direct) == .playable(.progressiveAudio))
        // The report's case is not part of its meaning.
        #expect(PlaybackFormatCompatibility.assess(mimeType: "AUDIO/MP4", kind: .direct) == .playable(.progressiveAudio))
    }

    @Test("other progressive audio containers AVPlayer supports are playable")
    func otherProgressiveContainers() {
        for mime in ["audio/flac", "audio/mpeg", "audio/aac", "audio/x-wav", "audio/alac"] {
            #expect(
                PlaybackFormatCompatibility.assess(mimeType: mime, kind: .direct) == .playable(.progressiveAudio),
                "\(mime) should be playable"
            )
        }
    }

    /// The honest half of the rule: YouTube offers Opus audio-only formats, this platform cannot play
    /// them, and there is no transcoder. Excluding them with a reason beats routing them into AVPlayer
    /// and failing on the user's screen.
    @Test("WebM and Ogg are refused, with the container named")
    func unsupportedContainersAreRefused() {
        for mime in ["audio/webm; codecs=\"opus\"", "video/webm", "audio/ogg", "application/ogg", "audio/opus"] {
            guard case let .unsupported(rejection) =
                PlaybackFormatCompatibility.assess(mimeType: mime, kind: .direct)
            else {
                Issue.record("\(mime) should not be playable")
                continue
            }
            #expect(rejection.reason.contains("AVPlayer"))
        }
    }

    @Test("a muxed MP4 with two codecs is playable, and is a muxed stream")
    func muxedMP4IsPlayable() {
        #expect(
            PlaybackFormatCompatibility.assess(
                mimeType: "video/mp4; codecs=\"avc1.640028, mp4a.40.2\"",
                kind: .direct
            ) == .playable(.muxedVideo)
        )
    }

    /// Video-only: it parses, it has a URL, and playing it would be silent.
    @Test("a single-codec video container carries no audio and is refused")
    func videoOnlyIsRefused() {
        #expect(
            PlaybackFormatCompatibility.assess(mimeType: "video/mp4; codecs=\"avc1.640028\"", kind: .direct)
                == .unsupported(.noAudioTrack("video/mp4"))
        )
        // A video container that reports no codecs at all cannot be shown to carry audio.
        #expect(
            PlaybackFormatCompatibility.assess(mimeType: "video/mp4", kind: .direct)
                == .unsupported(.noAudioTrack("video/mp4"))
        )
    }

    @Test("a manifest is adaptive, whatever its own top-level type says")
    func manifestIsAdaptive() {
        #expect(
            PlaybackFormatCompatibility.assess(mimeType: "application/x-mpegURL", kind: .hls)
                == .playable(.adaptiveManifest)
        )
        #expect(PlaybackFormatCompatibility.assess(mimeType: nil, kind: .hls) == .playable(.adaptiveManifest))
    }

    /// Absence of a report is not evidence of incompatibility: refusing an unlabelled plugin stream
    /// would break playback for providers that simply do not describe their formats.
    @Test("an unreported container is not treated as incompatible")
    func unreportedContainerIsPlayable() {
        #expect(PlaybackFormatCompatibility.assess(mimeType: nil, kind: .direct) == .playable(.progressiveAudio))
        #expect(PlaybackFormatCompatibility.assess(mimeType: "", kind: .direct) == .playable(.progressiveAudio))
        #expect(
            PlaybackFormatCompatibility.assess(mimeType: "audio/something-new", kind: .direct)
                == .playable(.progressiveAudio)
        )
    }

    /// A non-audio, non-video type is not something to guess about.
    @Test("an unrecognised non-media container is refused")
    func unrecognisedContainerIsRefused() {
        guard case .unsupported = PlaybackFormatCompatibility.assess(
            mimeType: "application/octet-stream",
            kind: .direct
        ) else {
            Issue.record("expected a refusal")
            return
        }
    }

    @Test("containers are split from their parameters and lowercased")
    func containerParsing() {
        #expect(PlaybackFormatCompatibility.container(from: "audio/mp4; codecs=\"mp4a.40.2\"") == "audio/mp4")
        #expect(PlaybackFormatCompatibility.container(from: "Video/MP4") == "video/mp4")
        #expect(PlaybackFormatCompatibility.container(from: "  audio/flac  ") == "audio/flac")
        #expect(PlaybackFormatCompatibility.container(from: nil) == nil)
        #expect(PlaybackFormatCompatibility.container(from: "") == nil)
    }

    @Test("codec parameters are read in order, and never renamed")
    func codecParsing() {
        #expect(
            PlaybackFormatCompatibility.codecs(in: "video/mp4; codecs=\"avc1.640028, mp4a.40.2\"")
                == ["avc1.640028", "mp4a.40.2"]
        )
        #expect(PlaybackFormatCompatibility.codecs(in: "audio/mp4; codecs=\"mp4a.40.2\"") == ["mp4a.40.2"])
        #expect(PlaybackFormatCompatibility.codecs(in: "audio/mp4") == [])
        #expect(PlaybackFormatCompatibility.codecs(in: nil) == [])
    }

    /// The reason is shown and logged, so it must be a statement about a format and nothing else.
    @Test("a rejection reason carries no URL, token or header")
    func rejectionReasonIsSafe() {
        let reason = PlaybackFormatRejection.containerNotSupported("audio/webm").reason
        #expect(!reason.contains("http"))
        #expect(!reason.contains("token"))
        #expect(reason.contains("audio/webm"))
        #expect(PlaybackFormatRejection.noAudioTrack("video/mp4").reason.contains("no reported audio"))
    }
}

@Suite("Player item event scope")
struct PlaybackItemScopeTests {
    private func item(_ name: String) -> AVPlayerItem {
        AVPlayerItem(url: URL(string: "https://cdn.example.com/\(name)")!)
    }

    @Test("an event for the item being played is delivered")
    func currentItemIsDelivered() {
        let current = item("current")
        #expect(PlaybackItemScope.isCurrent(eventItem: current, currentItem: current))
    }

    /// The bug this exists for: an outgoing item still reports its status and its failures after it
    /// has been replaced, and acting on them would re-resolve the track the user just chose.
    @Test("an event for the outgoing item is not delivered")
    func outgoingItemIsDropped() {
        #expect(!PlaybackItemScope.isCurrent(eventItem: item("outgoing"), currentItem: item("current")))
    }

    @Test("a stopped player has no current item, so nothing is delivered")
    func stoppedPlayerDeliversNothing() {
        #expect(!PlaybackItemScope.isCurrent(eventItem: item("detached"), currentItem: nil))
        #expect(!PlaybackItemScope.isCurrent(eventItem: nil, currentItem: item("current")))
        #expect(!PlaybackItemScope.isCurrent(eventItem: nil, currentItem: nil))
    }
}
