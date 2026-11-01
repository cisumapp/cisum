//
//  PlaybackFormatCompatibility.swift
//  PlaybackCore
//
//  Which parsed provider formats may be handed to AVPlayer. One policy, one place, with reasons.
//

import Foundation
import ProviderSDK

/// Why a parsed format was not turned into a candidate.
///
/// A reason rather than a bare `false`, because "why is this provider not being used" is the
/// question this whole pass exists to make answerable. The value is deliberately about the
/// *format*, never about a track or a URL, so it is safe to log and safe to show.
public enum PlaybackFormatRejection: Sendable, Equatable {
    /// The container cannot be played by AVPlayer on cisum's platforms. No transcoding exists and
    /// none is being added, so such a format is not a candidate at all.
    case containerNotSupported(String)
    /// A video container that carries no audio track — playing it would be silent.
    case noAudioTrack(String)

    /// A short, human-readable explanation. No URL, no credential, nothing platform-sensitive.
    public var reason: String {
        switch self {
        case let .containerNotSupported(container):
            "\(container) is not playable by AVPlayer on this platform"
        case let .noAudioTrack(container):
            "\(container) carries no reported audio track"
        }
    }
}

/// The verdict for one parsed format.
public enum PlaybackFormatVerdict: Sendable, Equatable {
    /// Playable, and how the bytes are delivered.
    case playable(TransportClass)
    /// Not a candidate, with the reason recorded.
    case unsupported(PlaybackFormatRejection)
}

/// Decides whether a provider's format description describes something this platform can play.
///
/// **This is the explicit form of a rule that used to be an implicit string prefix.** The YouTube
/// adapter previously said `mimeType.hasPrefix("audio/mp4")`, which was correct in effect but
/// unstated: it silently dropped Opus/WebM audio-only formats without recording that it had, and it
/// gave no answer at all for a container nobody had thought about. Both of those are the kind of
/// invisible decision that makes "which provider is playing and why" unanswerable.
///
/// What it must never do is *pretend*. There is no transcoding, no custom decoder and no second
/// playback engine in cisum, so a container AVPlayer cannot play is excluded — and excluded with a
/// reason — rather than routed hopefully into the player and failed on the user's screen. An
/// unknown `audio/*` type is treated as playable because absence of a report is not evidence of
/// incompatibility; a container cisum positively knows is unsupported is not.
public enum PlaybackFormatCompatibility {
    /// - Parameters:
    ///   - mimeType: The provider's own report, e.g. `"audio/mp4; codecs=\"mp4a.40.2\""`.
    ///   - kind: How the provider says the URL must be fetched. A manifest is decided by the
    ///     segment responses, not by its own top-level type.
    public static func assess(mimeType: String?, kind: SourceStream.Kind) -> PlaybackFormatVerdict {
        let type = container(from: mimeType)

        // A manifest's own type describes a playlist, not audio. Adaptive playback is AVPlayer's
        // native path for HLS, so the container it eventually delivers is decided per segment.
        if kind == .hls {
            return .playable(.adaptiveManifest)
        }

        guard let type else {
            // No container reported. That is an absence of information, not a report of
            // incompatibility, and refusing here would drop working plugin streams.
            return .playable(.progressiveAudio)
        }

        if adaptiveManifestTypes.contains(type) {
            return .playable(.adaptiveManifest)
        }

        if progressiveAudioTypes.contains(type) {
            return .playable(.progressiveAudio)
        }

        if unsupportedContainers.contains(type) {
            return .unsupported(.containerNotSupported(type))
        }

        if type.hasPrefix("video/") {
            // A video container is only usable when it carries an audio track. The provider says so
            // through a two-entry `codecs=` parameter — `"avc1.42001E, mp4a.40.2"` — which is the
            // documented shape of a muxed YouTube format. A single codec means video only.
            return codecs(in: mimeType).count > 1
                ? .playable(.muxedVideo)
                : .unsupported(.noAudioTrack(type))
        }

        if type.hasPrefix("audio/") {
            // An audio container cisum does not know about. Playable-by-default, for the reason
            // above: the adapter cannot prove it is broken, and AVPlayer is the arbiter.
            return .playable(.progressiveAudio)
        }

        return .unsupported(.containerNotSupported(type))
    }

    /// The type portion of a MIME type, lowercased, with parameters removed.
    ///
    /// Structural only — no table of friendly names and no codec interpretation. A provider's report
    /// is passed through as-is; this just separates it into the two fields the syntax defines.
    public static func container(from mimeType: String?) -> String? {
        guard let mimeType else { return nil }
        let type = mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return (type?.isEmpty ?? true) ? nil : type
    }

    /// The `codecs=` parameter's entries, in the order the provider listed them.
    ///
    /// Empty when the parameter is absent. Used only to tell a muxed format (two codecs) from a
    /// video-only one (one codec) — never to decide quality, and never mapped to a friendly name.
    public static func codecs(in mimeType: String?) -> [String] {
        guard let mimeType,
              let range = mimeType.range(of: "codecs=", options: .caseInsensitive)
        else { return [] }
        let raw = mimeType[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }

    /// Containers AVPlayer plays natively as a single progressive file.
    ///
    /// Explicit rather than "anything under audio/", because a wrong entry here is a silent
    /// playback failure and this list is small enough to keep honest.
    private static let progressiveAudioTypes: Set<String> = [
        "audio/mp4",
        "audio/x-m4a",
        "audio/m4a",
        "audio/aac",
        "audio/mpeg",
        "audio/mp3",
        "audio/flac",
        "audio/x-flac",
        "audio/alac",
        "audio/wav",
        "audio/x-wav",
        "audio/aiff",
        "audio/x-aiff",
        "audio/caf",
    ]

    /// Playlist types AVPlayer understands. Reached only for a `.direct` stream, since a `.hls`
    /// kind is already answered as adaptive.
    private static let adaptiveManifestTypes: Set<String> = [
        "application/x-mpegurl",
        "application/vnd.apple.mpegurl",
        "audio/x-mpegurl",
    ]

    /// Containers cisum positively knows this platform cannot play, with no transcoding available.
    ///
    /// WebM/Opus and Ogg are the real cases: YouTube offers them as adaptive audio and AVPlayer
    /// cannot open them, so exposing them would be a guaranteed failure rather than a quality win.
    /// Deciding this here, once, is also what stops a future adapter from re-discovering it.
    private static let unsupportedContainers: Set<String> = [
        "audio/webm",
        "video/webm",
        "audio/ogg",
        "video/ogg",
        "application/ogg",
        "audio/opus",
        "audio/x-opus",
    ]
}
