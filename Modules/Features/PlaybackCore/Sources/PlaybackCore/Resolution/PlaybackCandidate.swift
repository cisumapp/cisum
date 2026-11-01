//
//  PlaybackCandidate.swift
//  PlaybackCore
//
//  One way to play a track cisum has already identified. An identity plus a transport, not a URL.
//

import Foundation
import ProviderSDK

/// How confidently this candidate plays **the recording the user asked for**.
///
/// This is the gate the ranking policy is written around. A stream's quality is never allowed to
/// argue a candidate past a known identity disagreement: two candidates for different performances
/// are not comparable at all, so bitrate cannot resolve between them.
public enum CandidateIdentity: Sendable, Equatable {
    /// Ordering of the evidence tiers, strongest first.
    ///
    /// The order mirrors `CanonicalIdentityPolicy` in `Models`, which resolves identity in this same
    /// sequence — an established binding, then a valid ISRC, then a confident score. Keeping the two
    /// in the same order means the ranker cannot prefer evidence the identity layer would not.
    public enum Tier: Int, Sendable, Equatable {
        /// The matcher accepted this candidate on title/artist/duration alone.
        case confidentMatch = 1
        /// A valid ISRC was reported by both sides and agrees.
        case exactISRC = 2
        /// A persisted `(sourceID, sourceTrackID)` binding already exists for this song.
        case establishedBinding = 3
    }

    /// The candidate is this recording, to the stated degree.
    case confirmed(Tier)
    /// Nothing establishes the recording either way — an ad-hoc play of a fresh search result.
    ///
    /// Still playable. Unknown identity reduces certainty, it does not eliminate a candidate.
    case unconfirmed
    /// The candidate is known to be a **different** performance, live cut, remix or version.
    ///
    /// Rejected by the policy before any quality comparison happens.
    case incompatible(reason: String)

    /// Descending preference within the identity gate. `incompatible` never reaches the comparison.
    var rank: Int {
        switch self {
        case let .confirmed(tier): tier.rawValue
        case .unconfirmed: 0
        case .incompatible: -1
        }
    }

    /// Whether this candidate may be considered at all.
    var isUsable: Bool {
        if case .incompatible = self {
            return false
        }
        return true
    }
}

/// Where the media actually is.
public enum CandidateAvailability: Sendable, Equatable {
    /// Fetched from the provider over the network.
    case remote
    /// Already on this device — a downloaded or imported file.
    case local

    var rank: Int {
        switch self {
        case .local: 1
        case .remote: 0
        }
    }
}

/// Whether the candidate can be played in this environment at all.
///
/// DRM, account entitlement and region are the producers envisioned here. **No adapter in the repo
/// reports any of them yet**, so every candidate built today is `.eligible` — that is an honest
/// unknown, not a claim that every stream is playable. The gate exists so the first adapter that can
/// answer does not have to be threaded through the ranker as an afterthought.
public enum CandidateEligibility: Sendable, Equatable {
    case eligible
    case ineligible(reason: String)

    var isEligible: Bool {
        if case .eligible = self {
            return true
        }
        return false
    }
}

/// Trust in a source, as **cisum's runtime policy** judges it.
///
/// Deliberately not self-declared: a manifest claims nothing here, and an unverified plugin cannot
/// promote itself. The composition root answers this; where it does not, the answer is `.unknown`.
public enum SourceTrust: Sendable, Equatable {
    /// A provider cisum ships and compiles — a native adapter over a maintained SDK.
    case firstParty
    /// A user-installed plugin or declarative manifest.
    case thirdParty
    /// Nothing established it.
    case unknown

    /// Descending preference.
    var rank: Int {
        switch self {
        case .firstParty: 2
        case .thirdParty: 1
        case .unknown: 0
        }
    }
}

/// What backs a candidate's structured quality numbers.
///
/// The ranker must be able to tell a number the provider merely *said* from one cisum actually
/// observed, and neither from a blank. `SourceStream.bitrate` and friends are provider-reported in
/// every adapter that exists today, so `.verified` has no producer yet — it is stated here because
/// a probe that measures the delivered stream is the only thing that may ever claim it.
public enum QualityEvidence: Sendable, Equatable {
    /// Measured from the delivered stream.
    case verified
    /// Reported by the provider. What every current adapter supplies.
    case advertised
    /// Nothing is known. Never silently promoted to a value.
    case unknown

    var rank: Int {
        switch self {
        case .verified: 2
        case .advertised: 1
        case .unknown: 0
        }
    }
}

/// How the bytes are delivered, derived from structured fields only.
///
/// A progressive audio file seeks reliably and needs no per-segment work; an adaptive manifest is
/// the only option on some providers; a muxed file carries video cisum does not display. Ordered by
/// startup cost and by how much can go wrong, not by nominal quality.
public enum TransportClass: Sendable, Equatable {
    /// Direct file whose container is not video.
    case progressiveAudio
    /// An HLS manifest — adaptive, per-segment.
    case adaptiveManifest
    /// A direct file that carries video (muxed). Playable, heaviest.
    case muxedVideo

    /// Descending preference.
    var rank: Int {
        switch self {
        case .progressiveAudio: 2
        case .adaptiveManifest: 1
        case .muxedVideo: 0
        }
    }
}

/// A possible way to play an identified track, with the evidence needed to compare it with others.
///
/// A `SourceStream` alone cannot be ranked honestly: it knows nothing about *whose* stream it is,
/// whether that source can be trusted, or whether the recording is even the right one. Those three
/// questions live here so the ranking policy never has to guess them from a URL.
///
/// Everything a producer does not know stays unknown. There is no default codec, no assumed bitrate
/// and no stand-in provenance.
public struct PlaybackCandidate: Sendable, Equatable {
    /// The resolved transport. The only part `PlaybackEngine` needs.
    public let stream: SourceStream

    /// Which source produced this candidate — used for trust and for diagnostics.
    public let sourceID: String

    /// That source's track id. Opaque; only meaningful with `sourceID`.
    public let sourceTrackID: String

    /// How confidently this is the requested recording.
    public let identity: CandidateIdentity

    /// Local or remote.
    public let availability: CandidateAvailability

    /// Playable in this environment, or not.
    public let eligibility: CandidateEligibility

    /// Runtime trust in the source.
    public let trust: SourceTrust

    /// What backs the quality numbers this candidate reports.
    public let qualityEvidence: QualityEvidence

    /// Measured cost of obtaining this candidate, when a producer can measure it.
    ///
    /// `nil` is **unknown**, and unknown is neutral: the policy compares latency only when both
    /// sides report one, and otherwise falls through to the next tie-break rather than treating a
    /// missing measurement as a bad one. No producer measures per-candidate latency yet, because a
    /// single `streamCandidates` call returns the whole set at once — one duration for all of them.
    public let latencyMs: Double?

    /// The candidate's position in the adapter's own list.
    ///
    /// The final, always-decisive tie-break **within one source**. Two candidates the policy cannot
    /// separate are ordered by what the adapter said, which makes the result deterministic and
    /// independent of the order the caller happened to hand in.
    public let adapterIndex: Int

    /// The source's position in the caller's preference order, when the set spans several sources.
    ///
    /// A candidate set is no longer always one source's own list: resolution now collects
    /// candidates from every provider that already knows the track, so `adapterIndex` alone would
    /// not be unique across the set and the order would not be total. This is the tie-break above
    /// `adapterIndex`, and it is still only a tie-break: it decides between candidates the policy
    /// has already found *equal* on eligibility, identity, availability, quality, trust, delivery
    /// and latency. In particular it cannot make a 128 kbps stream from the requested source beat a
    /// lossless stream from another one — quality is compared first.
    ///
    /// Zero for a single-source set, which is the common case and the reason the default is 0.
    public let sourceOrder: Int

    public init(
        stream: SourceStream,
        sourceID: String,
        sourceTrackID: String,
        identity: CandidateIdentity = .unconfirmed,
        availability: CandidateAvailability = .remote,
        eligibility: CandidateEligibility = .eligible,
        trust: SourceTrust = .unknown,
        qualityEvidence: QualityEvidence = .advertised,
        latencyMs: Double? = nil,
        adapterIndex: Int = 0,
        sourceOrder: Int = 0
    ) {
        self.stream = stream
        self.sourceID = sourceID
        self.sourceTrackID = sourceTrackID
        self.identity = identity
        self.availability = availability
        self.eligibility = eligibility
        self.trust = trust
        self.qualityEvidence = qualityEvidence
        self.latencyMs = latencyMs
        self.adapterIndex = adapterIndex
        self.sourceOrder = sourceOrder
    }

    /// The stream as a quality comparison should see it.
    ///
    /// One adjustment, and only one: a **muxed** container's bitrate is dropped. That number covers
    /// video as well as audio, so comparing it against an audio-only bitrate compares two different
    /// quantities — and a stream type that makes a comparison invalid must not let a nominally
    /// larger number win one. Everything else is returned untouched; unknown stays unknown, and no
    /// field is defaulted.
    var qualityComparableStream: SourceStream {
        guard transportClass == .muxedVideo, stream.bitrate != nil else { return stream }
        return SourceStream(
            url: stream.url,
            kind: stream.kind,
            mimeType: stream.mimeType,
            bitrate: nil,
            bitDepth: stream.bitDepth,
            sampleRate: stream.sampleRate,
            qualityLabel: stream.qualityLabel,
            expiresAt: stream.expiresAt,
            isCacheable: stream.isCacheable,
            headers: stream.headers,
            durationSeconds: stream.durationSeconds
        )
    }

    /// Whether any structured **audio-quality** number is actually present.
    ///
    /// A provider that declares `.advertised` while reporting nothing has told us nothing, so the
    /// effective evidence is `.unknown` — the declaration cannot manufacture evidence.
    public var hasStructuredQuality: Bool {
        let comparable = qualityComparableStream
        return comparable.bitrate != nil || comparable.bitDepth != nil || comparable.sampleRate != nil
    }

    /// The provenance that applies, given what the candidate actually reports.
    public var evidence: QualityEvidence {
        hasStructuredQuality ? qualityEvidence : .unknown
    }

    /// Delivery class, derived from `SourceStream.Kind` and the container type.
    ///
    /// The container prefix (`video/`) is a statement about what the file holds, not a quality
    /// label — it is the one honest way to tell a muxed candidate from an audio-only one.
    public var transportClass: TransportClass {
        if stream.kind == .hls {
            return .adaptiveManifest
        }
        if let mime = stream.mimeType?.lowercased(), mime.hasPrefix("video/") {
            return .muxedVideo
        }
        return .progressiveAudio
    }
}
