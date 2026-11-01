//
//  RecordingVersion.swift
//  Models
//
//  Structured recording-version identity (Pass 2.6).
//
//  Replaces the ad-hoc "version type" string that canonical reconciliation used to guess from title
//  text on both sides of a comparison. It keeps three things distinct, which the old code conflated:
//   • a version a source *reports* (reported evidence, with provenance);
//   • a version only *inferred* from title text (the conservative fallback);
//   • a version that is genuinely *unknown*.
//
//  No provider currently reports a structured version, so in production the inferred fallback is
//  still what runs — but it now maps onto the same representation a reporting adapter will use, and
//  an inference can never be promoted to reported evidence.
//

import Foundation

/// The recording version of a track, coarse enough to be decided from real provider evidence.
///
/// Only categories with a demonstrated product need are listed: the four performance-changing
/// variants the identity gate must not merge across (`live`, `remix`, `acoustic`, `instrumental`),
/// the same-performance `remaster`, and `unknown`. Karaoke/cover/sped-up variants are *not* modelled
/// here because a title carrying those markers already fails the similarity check on its own, so
/// they never reach a confident merge.
public enum RecordingVersion: String, Sendable, Codable, CaseIterable {
    /// The original studio recording — and the default when a title carries no marker.
    case original
    /// A different master of the **same** performance. Compatible with `original`.
    case remaster
    /// A live performance — a materially different recording.
    case live
    case remix
    case acoustic
    case instrumental
    /// No evidence, or a marker the classifier does not recognise.
    case unknown

    /// The performance a version belongs to. Everything in one class is the same recorded
    /// performance for merge purposes; different classes never merge.
    public enum PerformanceClass: String, Sendable, Codable {
        case studio
        case live
        case remix
        case acoustic
        case instrumental
    }

    /// `nil` for `.unknown` — an unknown version cannot constrain a merge.
    public var performanceClass: PerformanceClass? {
        switch self {
        case .original, .remaster: .studio
        case .live: .live
        case .remix: .remix
        case .acoustic: .acoustic
        case .instrumental: .instrumental
        case .unknown: nil
        }
    }

    /// Whether two versions could be the same recording.
    ///
    /// A remaster is the same performance as the original and is compatible; a live take is not.
    /// `.unknown` is compatible with everything, because absence of evidence must not be read as a
    /// contradiction — the title-inference fallback is what supplies evidence when nobody reported it.
    public func isCompatible(with other: RecordingVersion) -> Bool {
        guard let mine = performanceClass, let theirs = other.performanceClass else { return true }
        return mine == theirs
    }
}

/// Where a version came from — the distinction the old title-string comparison could not represent.
public enum VersionEvidence: Sendable, Codable, Hashable {
    /// The source explicitly stated the version. Carries provenance.
    case reported(RecordingVersion, sourceID: String)
    /// Only inferred from title text. Never treated as stronger than reported evidence.
    case inferred(RecordingVersion)
    /// Nothing known.
    case unknown

    /// The version this evidence names, without the provenance.
    public var version: RecordingVersion {
        switch self {
        case let .reported(version, _), let .inferred(version): version
        case .unknown: .unknown
        }
    }

    /// Whether the version came from a source rather than title parsing.
    public var isReported: Bool {
        if case .reported = self {
            return true
        }
        return false
    }

    /// The reporting source, when the evidence is reported.
    public var sourceID: String? {
        if case let .reported(_, sourceID) = self {
            return sourceID
        }
        return nil
    }
}

/// Conservative title-based version inference — the fallback for sources that report nothing.
///
/// Provider-specific parsing belongs in the adapter; this classifier only understands the generic
/// marker words every provider's titles share, and it matches them as **whole words** so a word that
/// merely contains a marker (`Alive`, `Oliver`, `Deliver`) is not mistaken for one.
public enum VersionClassifier {
    /// Infers a version from a title, or `.original` when no marker is present.
    public static func infer(from title: String) -> RecordingVersion {
        let lowered = title.lowercased()
        for marker in Self.orderedMarkers
            where lowered.range(of: marker.pattern, options: .regularExpression) != nil
        {
            return marker.version
        }
        return .original
    }

    private struct Marker {
        let version: RecordingVersion
        let pattern: String
    }

    /// Order is deliberate: when a title advertises several markers, the most performance-changing
    /// one wins deterministically. `remaster` is last because it is the weakest signal (same
    /// performance, different master).
    private static let orderedMarkers: [Marker] = [
        Marker(version: .live, pattern: #"\blive\b"#),
        Marker(version: .remix, pattern: #"\bremix\b"#),
        Marker(version: .acoustic, pattern: #"\bacoustic\b"#),
        Marker(version: .instrumental, pattern: #"\binstrumental\b"#),
        Marker(version: .remaster, pattern: #"\bremaster(?:ed)?\b"#),
    ]
}

/// How evidence is combined. Pure, so the rules are testable without a store.
public enum VersionEvidencePolicy {
    /// The version to gate a comparison on: reported evidence first, then inferred, then — when
    /// nothing at all is known — a conservative inference from the raw title.
    ///
    /// - Parameters:
    ///   - evidence: What the caller knows about this side, if anything.
    ///   - rawTitle: The **un-normalised** title, so the fallback can see the version markers that
    ///     `CanonicalSongReconciler.normalize` strips.
    public static func resolvedVersion(_ evidence: VersionEvidence?, rawTitle: String) -> RecordingVersion {
        switch evidence {
        case let .reported(version, _): version
        case let .inferred(version): version
        case .unknown, .none: VersionClassifier.infer(from: rawTitle)
        }
    }

    /// Merges newly-observed evidence into what is already known.
    ///
    /// Deterministic and conservative:
    /// - `unknown` never overwrites known evidence (either direction);
    /// - reported evidence outranks inferred evidence;
    /// - when two reported versions disagree, the **existing** evidence is kept — a conflict is not
    ///   resolved by flip-flopping, it is left as the first established value so repeated imports
    ///   cannot oscillate.
    public static func merged(existing: VersionEvidence, incoming: VersionEvidence) -> VersionEvidence {
        switch (existing, incoming) {
        case let (.unknown, incoming): incoming
        case let (existing, .unknown): existing
        case (.inferred, .reported): incoming
        case (.reported, .inferred): existing
        case (.reported, .reported), (.inferred, .inferred): existing
        }
    }
}
