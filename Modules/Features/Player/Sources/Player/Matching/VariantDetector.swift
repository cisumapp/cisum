//
//  VariantDetector.swift
//  Player
//
//  Telling the original recording apart from everything that isn't.
//

import Foundation

/// What kind of recording a search result appears to be.
///
/// The distinction the previous architecture kept losing: a karaoke version matches the title
/// *perfectly*, so anything scoring on title similarity alone ranks it top. Users notice.
public enum RecordingVariant: String, Sendable, CaseIterable {
    /// No variant markers found. The presumed original studio recording.
    case original
    case live
    case remix
    case acoustic
    case instrumental
    case karaoke
    case cover
    case remastered
    case extended
    case radioEdit
    case spedUp
    case slowed
    case nightcore
    case demo

    /// Whether this is a materially different performance, not just a different master.
    ///
    /// `remastered` and `radioEdit` are the same performance and are usually acceptable
    /// substitutes; a live take or a karaoke backing track is not.
    public var isDifferentPerformance: Bool {
        switch self {
        case .original, .remastered, .radioEdit, .extended:
            false
        case .live, .remix, .acoustic, .instrumental, .karaoke, .cover, .spedUp, .slowed,
             .nightcore, .demo:
            true
        }
    }

    /// Variants that are almost never what someone asked for unless they said so.
    public var isUsuallyUnwanted: Bool {
        switch self {
        case .karaoke, .instrumental, .cover, .nightcore:
            true
        default:
            false
        }
    }
}

/// Detects variant markers in titles.
public enum VariantDetector {
    /// Every variant a title advertises.
    ///
    /// Letter-spaced titles are collapsed first — `"s l o w e d + r e v e r b"` is a real and
    /// common pattern that otherwise defeats word matching completely.
    public static func detect(in title: String) -> Set<RecordingVariant> {
        let haystack = " " + TextNormalizer.normalize(
            TextNormalizer.collapseSpacedLetters(title) + " " + title
        ) + " "

        var found: Set<RecordingVariant> = []
        for (variant, markers) in Self.markers {
            if markers.contains(where: { haystack.contains(" \($0) ") || haystack.contains(" \($0)") }) {
                found.insert(variant)
            }
        }
        return found
    }

    /// The single most representative variant, for display and coarse comparison.
    public static func primary(in title: String) -> RecordingVariant {
        let found = detect(in: title)
        // Order matters: a "Live (Karaoke Version)" is a karaoke track first and foremost.
        for candidate in [RecordingVariant.karaoke, .instrumental, .cover, .nightcore,
                          .spedUp, .slowed, .remix, .live, .acoustic, .demo,
                          .extended, .radioEdit, .remastered] where found.contains(candidate) {
            return candidate
        }
        return .original
    }

    /// Whether a candidate is acceptable for a query that did not ask for a variant.
    ///
    /// - Parameter queryVariants: Variants the *user* asked for. A search for "song live" should
    ///   get the live version, so an explicitly requested variant is never penalised.
    public static func isAcceptable(
        candidateTitle: String,
        queryVariants: Set<RecordingVariant>
    ) -> Bool {
        let candidate = detect(in: candidateTitle)
        let unrequested = candidate.subtracting(queryVariants)

        // Anything the user did not ask for that changes the performance disqualifies it.
        return !unrequested.contains { $0.isDifferentPerformance }
    }

    private static let markers: [RecordingVariant: [String]] = [
        .live: ["live", "en vivo", "en directo", "concert", "unplugged", "session", "tour"],
        .remix: ["remix", "rmx", "bootleg", "flip", "vip mix", "edit by", "mashup"],
        .acoustic: ["acoustic", "acustico", "akustik"],
        .instrumental: ["instrumental", "backing track", "no vocals", "off vocal"],
        .karaoke: ["karaoke", "sing along", "singalong", "in the style of", "made popular by"],
        .cover: ["cover", "tribute", "as made famous by", "originally performed by"],
        .remastered: ["remaster", "remastered", "anniversary edition", "deluxe remaster"],
        .extended: ["extended", "extended mix", "long version", "full length"],
        .radioEdit: ["radio edit", "radio version", "single version", "clean version"],
        .spedUp: ["sped up", "spedup", "speed up", "faster"],
        .slowed: ["slowed", "slow down", "slowed reverb", "reverb"],
        .nightcore: ["nightcore"],
        .demo: ["demo", "rough mix", "work tape"],
    ]
}
