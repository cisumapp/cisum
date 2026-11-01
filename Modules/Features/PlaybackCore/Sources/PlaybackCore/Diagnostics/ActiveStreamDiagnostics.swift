//
//  ActiveStreamDiagnostics.swift
//  PlaybackCore
//
//  What is *actually* playing right now — and the honest way to describe it.
//
//  A debugging surface: it exists so candidate ranking, provider choice and fallback can be seen
//  working (or not) without attaching Instruments. It is deliberately derived from the resolved
//  candidate that `PlaybackEngine` was handed, never from the search result the user tapped, the
//  canonical `Song`, or the highest-ranked candidate that did not get played.
//

import Foundation

/// The stream playback is using, reduced to what is safe and useful to display.
///
/// **No URL, no headers, no tokens.** Not by convention — those values are structurally absent, so
/// no formatting bug can leak a signed `googlevideo` URL or an authorization header into the UI.
/// What is here is what a provider *reported* about the stream, plus which source served it.
public struct ActiveStreamInfo: Sendable, Equatable {
    /// The provider's id, e.g. `"youtube_music"`.
    public let sourceID: String
    /// The provider's display name, when the registry knows it.
    public let sourceDisplayName: String?
    /// The container/type the provider reported, e.g. `"audio/mp4"`. Parameters stripped.
    public let container: String?
    /// The codec token as reported in the MIME type's `codecs=` parameter, when present.
    ///
    /// Verbatim — `"mp4a.40.2"`, `"opus"` — because mapping it to a marketing name ("AAC") is
    /// exactly the kind of label-reading this architecture removed.
    public let codec: String?
    public let bitrate: Int?
    public let sampleRate: Int?
    public let bitDepth: Int?
    /// Whether the numbers above were measured, reported, or unknown.
    public let evidence: QualityEvidence
    /// How the bytes are delivered.
    public let transportClass: TransportClass
    /// True when this is not the candidate ranking selected first, but a fallback that replaced it.
    public let isFallback: Bool

    public init(
        sourceID: String,
        sourceDisplayName: String? = nil,
        container: String? = nil,
        codec: String? = nil,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        evidence: QualityEvidence = .unknown,
        transportClass: TransportClass = .progressiveAudio,
        isFallback: Bool = false
    ) {
        self.sourceID = sourceID
        self.sourceDisplayName = sourceDisplayName
        self.container = container
        self.codec = codec
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.evidence = evidence
        self.transportClass = transportClass
        self.isFallback = isFallback
    }

    /// Describes the candidate `PlaybackEngine` was actually handed.
    public init(candidate: PlaybackCandidate, sourceDisplayName: String?, isFallback: Bool) {
        let parts = Self.splitMIME(candidate.stream.mimeType)
        self.init(
            sourceID: candidate.sourceID,
            sourceDisplayName: sourceDisplayName,
            container: parts.container,
            codec: parts.codec,
            bitrate: candidate.stream.bitrate,
            sampleRate: candidate.stream.sampleRate,
            bitDepth: candidate.stream.bitDepth,
            evidence: candidate.evidence,
            transportClass: candidate.transportClass,
            isFallback: isFallback
        )
    }

    /// Splits `"audio/mp4; codecs=\"mp4a.40.2\""` into its type and codec.
    ///
    /// A structural split on the MIME syntax only — the type portion and the `codecs=` parameter.
    /// No table of friendly names, because a lookup table is what turns a report into a claim.
    static func splitMIME(_ mimeType: String?) -> (container: String?, codec: String?) {
        guard let mimeType, !mimeType.isEmpty else { return (nil, nil) }
        let pieces = mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
        let container = pieces.first.map { $0.trimmingCharacters(in: .whitespaces) }
        var codec: String?
        if pieces.count > 1 {
            let parameters = pieces[1]
            if let range = parameters.range(of: "codecs=", options: .caseInsensitive) {
                codec = parameters[range.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        return (container?.isEmpty == true ? nil : container, codec?.isEmpty == true ? nil : codec)
    }
}

/// What the player can say about the active stream, including "nothing yet".
///
/// The states are explicit rather than represented by a nil stream so the UI can distinguish
/// "resolving" from "failed" from "nothing has ever played" — three situations that a single
/// optional would collapse into the same misleading blank.
public enum ActiveStreamState: Sendable, Equatable {
    /// Nothing has been requested.
    case idle
    /// A request is in flight; the stream is not known yet.
    case resolving
    /// This is the stream playback is using.
    case active(ActiveStreamInfo)
    /// The request failed before any stream became active.
    case failed
}

/// Owns the active-stream state and the generation that makes updates safe.
///
/// Mirrors `PlaybackStartupTracker`: one generation per playback request, and a result that arrives
/// for a superseded request is ignored rather than displayed. That is the whole mechanism behind
/// "switching tracks cannot leave stale diagnostic information visible" — the guard is here, pure
/// and testable, instead of being an informal invariant spread across the view model.
public struct ActiveStreamTracker: Sendable {
    public private(set) var state: ActiveStreamState

    /// The playback request the current state belongs to.
    public private(set) var requestID: Int

    public init(state: ActiveStreamState = .idle, requestID: Int = 0) {
        self.state = state
        self.requestID = requestID
    }

    /// Starts a new request, superseding any in-flight one.
    ///
    /// The id is the caller's — the same monotonic playback-request id the startup proxy uses, so
    /// there is one notion of "which request is current" rather than two that can drift.
    public mutating func begin(requestID: Int) {
        self.requestID = requestID
        state = .resolving
    }

    /// Marks the failure of the request.
    ///
    /// - Returns: `true` if this was the current request and the state changed.
    @discardableResult
    public mutating func fail(requestID: Int) -> Bool {
        guard requestID == self.requestID else { return false }
        state = .failed
        return true
    }

    /// Records the stream playback is now using.
    ///
    /// - Returns: `true` if this was the current request; `false` means the update was stale and
    ///   the state was left alone.
    @discardableResult
    public mutating func activate(
        requestID: Int,
        candidate: PlaybackCandidate,
        sourceDisplayName: String?,
        isFallback: Bool
    ) -> Bool {
        guard requestID == self.requestID else { return false }
        state = .active(
            ActiveStreamInfo(
                candidate: candidate,
                sourceDisplayName: sourceDisplayName,
                isFallback: isFallback
            )
        )
        return true
    }

    /// Clears everything and invalidates any in-flight request.
    public mutating func stop() {
        requestID &+= 1
        state = .idle
    }
}

/// One row of the diagnostic detail view.
public struct ActiveStreamDiagnosticRow: Sendable, Equatable, Identifiable {
    public let label: String
    public let value: String
    public var id: String {
        label
    }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Formats active-stream state for display. Shared so iOS and macOS cannot describe the same
/// session differently.
public enum ActiveStreamDiagnostic {
    /// Shown in place of a value that is not known. Never a fabricated default.
    public static let unknown = "Unknown"

    /// One line for the player, e.g. `"YouTube Music · audio/mp4 · 128 kbps"`.
    ///
    /// Unknown parts are omitted rather than printed as "Unknown" — a short line that says what is
    /// known is more useful than a long one that repeats what is not.
    public static func summary(_ state: ActiveStreamState) -> String? {
        switch state {
        case .idle:
            return nil
        case .resolving:
            return "Resolving stream…"
        case .failed:
            return "Stream unavailable"
        case let .active(info):
            var parts: [String] = []
            if info.isFallback {
                parts.append("Fallback")
            }
            parts.append(info.sourceDisplayName ?? info.sourceID)
            if let container = info.container {
                parts.append(container)
            }
            if let codec = info.codec {
                parts.append(codec)
            }
            if let bitrate = info.bitrate {
                parts.append(bitrateLabel(bitrate))
            }
            if let sampleRate = info.sampleRate {
                parts.append(sampleRateLabel(sampleRate))
            }
            if let bitDepth = info.bitDepth {
                parts.append("\(bitDepth)-bit")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// The full detail, as label/value rows, for a diagnostics list or a tooltip.
    ///
    /// Always reports every field, using `unknown` where nothing is known — this is the surface a
    /// developer reads when the summary line looks wrong.
    public static func rows(_ state: ActiveStreamState) -> [ActiveStreamDiagnosticRow] {
        var rows: [ActiveStreamDiagnosticRow] = [
            .init(label: "Status", value: statusLabel(state)),
        ]
        guard case let .active(info) = state else { return rows }

        rows.append(.init(label: "Source", value: info.sourceDisplayName ?? info.sourceID))
        rows.append(.init(label: "Stream", value: transportLabel(info.transportClass)))
        rows.append(.init(label: "Container", value: info.container ?? unknown))
        rows.append(.init(label: "Codec", value: info.codec ?? unknown))
        rows.append(.init(label: "Bitrate", value: info.bitrate.map(bitrateLabel) ?? unknown))
        rows.append(.init(label: "Sample Rate", value: info.sampleRate.map(sampleRateLabel) ?? unknown))
        rows.append(.init(label: "Bit Depth", value: info.bitDepth.map { "\($0)-bit" } ?? unknown))
        rows.append(.init(label: "Quality Evidence", value: evidenceLabel(info.evidence)))
        rows.append(.init(label: "Fallback", value: info.isFallback ? "Yes" : "No"))
        return rows
    }

    // MARK: - Formatting

    /// Bits per second as kbps. Rounds, because the exact figure is not what a diagnostic line is
    /// for and the provider's own number is often an estimate.
    public static func bitrateLabel(_ bitrate: Int) -> String {
        let kbps = Double(bitrate) / 1000
        return "\(Int(kbps.rounded())) kbps"
    }

    /// Samples per second as kHz, keeping one decimal for values that are not whole.
    public static func sampleRateLabel(_ sampleRate: Int) -> String {
        let kHz = Double(sampleRate) / 1000
        return kHz == kHz.rounded() ? "\(Int(kHz)) kHz" : String(format: "%.1f kHz", kHz)
    }

    public static func evidenceLabel(_ evidence: QualityEvidence) -> String {
        switch evidence {
        case .verified: "measured"
        case .advertised: "provider-reported"
        case .unknown: "unknown"
        }
    }

    public static func transportLabel(_ transport: TransportClass) -> String {
        switch transport {
        case .progressiveAudio: "progressive audio"
        case .adaptiveManifest: "adaptive manifest (HLS)"
        case .muxedVideo: "muxed audio+video"
        }
    }

    public static func statusLabel(_ state: ActiveStreamState) -> String {
        switch state {
        case .idle: "Idle"
        case .resolving: "Resolving"
        case .failed: "Failed"
        case let .active(info): info.isFallback ? "Playing (fallback)" : "Playing"
        }
    }
}
