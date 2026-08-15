//
//  StreamSelector.swift
//  Player
//
//  Choosing the best stream, by arithmetic on numbers rather than parsing prose.
//

import Foundation
import ProviderSDK

/// Ranks streams of an already-identified track.
///
/// **Quality is compared using structured fields only.** The previous implementation had
/// `ProviderSDKStreamResolver.mimeType(for:)` *serialise* codec and bitrate into a MIME-ish string
/// specifically so `PlaybackURLResolver.qualityScore(for:)` could parse them back out — with a
/// code comment admitting it. Structured data was destroyed at a package boundary and
/// reconstructed by string-parsing on the other side. That round-trip does not return.
///
/// The provider's own quality *label* is never consulted, because there is no shared vocabulary:
/// `"FLAC 16-bit / 44.1 kHz"`, `"LOSSLESS"`, `"320kbps"`, `"DOLBY ATMOS"`, and `"YTM HLS"` all
/// appear for comparable streams.
public struct StreamSelector: Sendable {
    /// What the user asked for.
    public var preferred: QualityHint

    /// Whether lossless should win even at a large size cost.
    public var prefersLossless: Bool

    public init(preferred: QualityHint = .high, prefersLossless: Bool = true) {
        self.preferred = preferred
        self.prefersLossless = prefersLossless
    }

    /// The best of several streams, or `nil` if there are none.
    public func best(from streams: [SourceStream]) -> SourceStream? {
        streams.max { score($0) < score($1) }
    }

    /// Ranks a stream. Higher is better.
    ///
    /// Deliberately transparent arithmetic — the ordering should be obvious from reading it, and
    /// reproducible in a test, rather than emerging from a pile of string heuristics.
    public func score(_ stream: SourceStream) -> Double {
        var total: Double = 0

        // Bit depth and sample rate are the clearest lossless signal when reported.
        if let bitDepth = stream.bitDepth {
            total += bitDepth >= 24 ? 40 : 25
        }
        if let sampleRate = stream.sampleRate {
            total += sampleRate > 48000 ? 20 : 10
        }

        // Codec, from the MIME type only — a container/codec identifier, not a quality string.
        if let mime = stream.mimeType?.lowercased() {
            if mime.contains("flac") || mime.contains("alac") || mime.contains("wav") {
                total += prefersLossless ? 50 : 20
            } else if mime.contains("opus") {
                total += 18
            } else if mime.contains("aac") || mime.contains("mp4") || mime.contains("m4a") {
                total += 15
            } else if mime.contains("mpeg") || mime.contains("mp3") {
                total += 10
            }
        }

        // Bitrate, when reported, scaled so it refines rather than dominates.
        if let bitrate = stream.bitrate {
            total += min(Double(bitrate) / 32000, 20)
        }

        // A progressive file seeks reliably and starts faster than an adaptive manifest, so it
        // wins all else being equal. Not a large penalty — HLS is often the only option.
        if stream.kind == .hls {
            total -= 5
        }

        // A stream that cannot be cached costs a network round trip on every play.
        if !stream.isCacheable {
            total -= 2
        }

        return total
    }
}
