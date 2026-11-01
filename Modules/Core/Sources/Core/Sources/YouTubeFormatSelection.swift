//
//  YouTubeFormatSelection.swift
//  Core
//
//  Which of YouTube's parsed formats become playback candidates, and why.
//

import Foundation
import Player
import ProviderSDK
import Utilities
import YouTubeSDK

// `Player` re-exports `PlaybackCore`, which owns the decision about what AVPlayer can play. Format
// compatibility is playback policy rather than this adapter's private opinion, so a second adapter
// cannot answer the same question differently.

/// Turns YouTube's parsed formats into the streams cisum offers to the ranker.
///
/// Pure, and deliberately separate from the player-info request, for two reasons: the decision is the
/// reviewable part — which parsed formats are usable here, in what order, fetched with which headers —
/// and it is the part that can be exercised without a live `PlayerInfo`. Every format goes through
/// `PlaybackFormatCompatibility`, so "why is this format not being used" has exactly one answer and it
/// is recorded.
///
/// **This list is not what decides playback.** `CandidateRankingPolicy` orders the candidates; a
/// position in this array survives only as the tie-break between candidates that are equal on every
/// other dimension. The order here is YouTube's own preference for *fallback* purposes: audio-only
/// best-first, then muxed.
enum YouTubeFormatSelection {
    /// Builds the candidate streams for one resolved player response.
    ///
    /// - Parameters:
    ///   - hlsURL: The adaptive manifest, when the response carried one.
    ///   - formats: Every parsed format, muxed and adaptive together.
    ///   - expiry: When the URLs stop working, when it is known. `nil` means unknown, and the store
    ///     applies its own conservative default rather than this file inventing one.
    static func candidates(
        hlsURL: URL?,
        formats: [InternalVideoFormat],
        expiry: Date?
    ) -> [SourceStream] {
        var candidates: [SourceStream] = []

        // The manifest first, which is the position this list has always given it. Its segments are
        // fetched through the same WebSafari client, and the ones under `manifest.googlevideo.com`
        // each need a `pot=` token injected by the resource loader.
        if let hlsURL {
            candidates.append(SourceStream(
                url: hlsURL,
                kind: .hls,
                mimeType: "application/x-mpegURL",
                qualityLabel: "Adaptive",
                expiresAt: expiry,
                headers: [userAgentHeader: userAgent(for: hlsURL)]
            ))
        }

        var audioOnly: [InternalVideoFormat] = []
        var muxed: [InternalVideoFormat] = []
        var notPlayable: [String] = []
        var seen = Set<String>()

        for format in formats where format.url != nil {
            // The same itag can appear more than once with different URLs, from different clients. Two
            // candidates for one format would spend a fallback on the same audio.
            guard seen.insert("\(format.itag)-\(format.mimeType)").inserted else { continue }

            switch PlaybackFormatCompatibility.assess(mimeType: format.mimeType, kind: .direct) {
            case .playable(.muxedVideo):
                muxed.append(format)
            case .playable:
                audioOnly.append(format)
            case let .unsupported(rejection):
                let container = PlaybackFormatCompatibility.container(from: format.mimeType) ?? "container not reported"
                notPlayable.append("itag=\(format.itag) \(container) — \(rejection.reason)")
            }
        }

        // Audio-only, best reported bitrate first. The second-best audio format is exposed as well: a
        // CDN rejection of one URL is a real and common failure, and the next audio-only format is a
        // better fallback than a video container.
        for format in audioOnly.sorted(by: { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }) {
            guard let url = format.url else { continue }
            candidates.append(SourceStream(
                url: url,
                kind: .direct,
                // The format's own MIME type, `codecs=` parameter included: YouTube names the codec
                // there (`mp4a.40.2`), and that is a report about this format rather than a label cisum
                // has to interpret. A reported `0` is treated as "not reported".
                mimeType: format.mimeType,
                bitrate: format.bitrate.flatMap { $0 > 0 ? $0 : nil },
                expiresAt: expiry,
                headers: [userAgentHeader: userAgent(for: url)],
                durationSeconds: reportedDuration(url)
            ))
        }

        // Muxed last on quality, but it is the candidate with no strings attached: an Android-signed
        // progressive URL that needs only the Android UA — no manifest, no per-segment token, no
        // resource-loader delegate.
        //
        // **No bitrate is carried for it, deliberately.** A muxed format's `bitrate` covers video and
        // audio together, so handing it to the ranker as if it were audio quality would let a heavier
        // video stream win a comparison it has no evidence for. The container (`video/mp4`) is reported,
        // which is what tells the ranker this candidate carries video.
        for format in muxed.sorted(by: { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }) {
            guard let url = format.url else { continue }
            candidates.append(SourceStream(
                url: url,
                kind: .direct,
                mimeType: format.mimeType,
                expiresAt: expiry,
                headers: [userAgentHeader: userAgent(for: url)],
                durationSeconds: reportedDuration(url)
            ))
        }

        // Bounded and URL-free: a count, and the first few reasons. This is the record of *why* a
        // parsed format never became a candidate, which used to be invisible.
        if !notPlayable.isEmpty {
            let shown = notPlayable.prefix(5).joined(separator: "; ")
            PerfLog.info("YouTubeSource: \(notPlayable.count) parsed format(s) not playable by AVPlayer — \(shown)\(notPlayable.count > 5 ? " …" : "")")
        }

        return candidates
    }

    /// The file's exact length from the URL's `dur` parameter (seconds, to the millisecond).
    ///
    /// AVFoundation only estimates the length of YouTube's fragmented-MP4 audio, and the estimate
    /// was measured at double the real length; `dur` is YouTube's own statement for this file.
    static func reportedDuration(_ url: URL) -> Double? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "dur" }?.value.flatMap(Double.init)
    }

    /// The User-Agent of the client that signed `url`. A fixed WebSafari header made every URL from
    /// the TV, MWEB and Android VR clients unplayable with a 403.
    static func userAgent(for url: URL) -> String {
        InnerTubeClients.userAgent(forStreamURL: url)
    }

    /// The header name the media request carries the client's User-Agent under.
    ///
    /// Named once because a mismatch here is silent: the CDN rejects the request, AVFoundation reports
    /// only `CRABS ... ReadError` in the system log, and the player sits at 0:00.
    static let userAgentHeader = "User-Agent"
}
