import Authentication
import Foundation
import Models
import Utilities

extension SearchViewModel {
    nonisolated func performFallbackMatch(
        title: String,
        artist: String,
        duration: TimeInterval?,
        sourceISRC: String?,
        candidates: [FederatedSearchItem]
    ) async -> SpotifyFallbackMatch? {
        findBestSpotifyFallbackMatch(
            for: title,
            artist: artist,
            durationSeconds: duration,
            sourceISRC: sourceISRC,
            in: candidates
        )
    }

    struct SpotifyFallbackMatch {
        let item: FederatedSearchItem
        let score: Double
    }

    nonisolated func findBestSpotifyFallbackMatch(
        for title: String,
        artist: String,
        durationSeconds: TimeInterval?,
        sourceISRC: String? = nil,
        in items: [FederatedSearchItem]
    ) -> SpotifyFallbackMatch? {
        let rankedMatches = items.compactMap { item -> SpotifyFallbackMatch? in
            guard item.isPlayable else { return nil }
            let score = spotifyFallbackScore(
                sourceTitle: title,
                sourceArtist: artist,
                sourceDuration: durationSeconds,
                sourceISRC: sourceISRC,
                candidate: item
            )

            guard score >= 0.55 else { return nil }
            return SpotifyFallbackMatch(item: item, score: score)
        }

        return rankedMatches.max(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return providerPriority(for: lhs.item.service) < providerPriority(for: rhs.item.service)
            }

            return lhs.score < rhs.score
        })
    }

    private nonisolated func spotifyFallbackScore(
        sourceTitle: String,
        sourceArtist: String,
        sourceDuration: TimeInterval?,
        sourceISRC: String?,
        candidate: FederatedSearchItem
    ) -> Double {
        // ISRC exact match: near-perfect score. ISRC is the gold standard for
        // identifying the same recording across providers.
        if let sourceISRC, !sourceISRC.isEmpty {
            let candidateISRC: String? = switch candidate.payload {
            case let .providerSDK(ref):
                ref.representations.first?.isrc
            case let .spotify(track):
                track.isrc
            default:
                nil
            }
            if let candidateISRC, candidateISRC == sourceISRC {
                return 1.0
            }
        }

        let normalizedSourceTitle = normalizedRankingText(sourceTitle)
        let normalizedSourceArtist = normalizedRankingText(sourceArtist)
        let normalizedCandidateTitle = normalizedRankingText(candidate.title)
        let normalizedCandidateArtist = normalizedRankingText(primaryArtistName(from: candidate.subtitle))
        // Full candidate text — YouTube results often embed the artist in the title/channel
        // ("Michael Jackson - Rock With You") rather than a clean artist field.
        let normalizedCandidateText = normalizedRankingText("\(candidate.title) \(candidate.subtitle)")

        let titleOverlap = tokenOverlapScore(normalizedSourceTitle, normalizedCandidateTitle)
        let parsedArtistOverlap = tokenOverlapScore(normalizedSourceArtist, normalizedCandidateArtist)
        let artistPresence = tokenOverlapScore(normalizedSourceArtist, normalizedCandidateText)
        let artistOverlap = max(parsedArtistOverlap, artistPresence)

        // Artist gate: a known source artist that shares NO token anywhere in the candidate is
        // almost certainly a different song that happens to have the same title (e.g. "Rock With
        // You" by Michael Jackson vs by SEVENTEEN). Reject it (score below the 0.55 threshold).
        if !normalizedSourceArtist.isEmpty, artistOverlap == 0 {
            return 0
        }

        // Title gate: mirror the artist gate. A candidate that shares NO title token with the
        // source and is not a substring match either way is a different song that merely shares
        // the artist (e.g. "Ik Kudi Acoustic" by Paresh Pahuja resolving to his "Dooron Dooron").
        if Self.titleGateRejects(
            sourceTitle: normalizedSourceTitle,
            candidateTitle: normalizedCandidateTitle,
            titleOverlap: titleOverlap
        ) {
            return 0
        }
        let titleContainsBonus = normalizedCandidateTitle.contains(normalizedSourceTitle) ? 0.16 : 0
        let sourceContainsBonus = normalizedSourceTitle.contains(normalizedCandidateTitle) ? 0.08 : 0
        let exactTitleBonus = normalizedSourceTitle == normalizedCandidateTitle ? 0.36 : 0
        let exactArtistBonus = normalizedSourceArtist == normalizedCandidateArtist ? 0.18 : 0
        let durationBonus = spotifyDurationMatchScore(
            sourceDuration: sourceDuration,
            candidateDuration: candidate.durationSeconds
        ) * 0.34
        let variantPenalty = spotifyVariantPenalty(
            sourceTitle: normalizedSourceTitle,
            candidateTitle: normalizedCandidateTitle
        )

        let providerBonus: Double = switch candidate.service {
        case .youtubeMusic:
            0.05
        case .youtube:
            0.03
        case .spotify:
            0
        case .providerSDK:
            // Native provider metadata is as accurate as YouTube Music for fallback matching.
            0.05
        }

        return (0.42 * titleOverlap)
            + (0.30 * artistOverlap)
            + titleContainsBonus
            + sourceContainsBonus
            + exactTitleBonus
            + exactArtistBonus
            + durationBonus
            + providerBonus
            + variantPenalty
    }

    private nonisolated func spotifyDurationMatchScore(sourceDuration: TimeInterval?, candidateDuration: TimeInterval?) -> Double {
        guard let sourceDuration, sourceDuration > 0 else { return 0.12 }
        guard let candidateDuration, candidateDuration > 0 else { return 0.12 }

        let delta = abs(sourceDuration - candidateDuration)
        let baseline = max(sourceDuration, candidateDuration, 1)
        let normalizedDelta = min(delta / baseline, 1)

        return max(0, 1 - (normalizedDelta * 3.5))
    }

    private nonisolated func spotifyVariantPenalty(sourceTitle: String, candidateTitle: String) -> Double {
        let sourceHasVariant = spotifyTitleHasVariantMarker(sourceTitle)
        let candidateHasVariant = spotifyTitleHasVariantMarker(candidateTitle)

        if candidateHasVariant, !sourceHasVariant {
            return -0.34
        }

        if sourceHasVariant, !candidateHasVariant {
            return -0.08
        }

        return 0
    }

    private nonisolated func spotifyTitleHasVariantMarker(_ title: String) -> Bool {
        let markers = [
            " remix",
            " live",
            " acoustic",
            " cover",
            " instrumental",
            " karaoke",
            " tribute",
            " mashup",
            " medley",
            " rework",
            " edit",
            " slowed",
            " sped up",
            " nightcore",
            " 8d",
            " mono",
            " remaster",
            " version",
            " stripped",
            " piano version",
            " orchestral",
            " unplugged",
            " demo",
            " session",
            " reprise",
            " interlude",
            " lo-fi",
            " lofi",
            " deluxe",
            " special edition",
            " bonus track",
            " live at",
            " performed by",
            " ft.",
            " feat.",
            " × ",
            " vs ",
            " x ",
            " vs. ",
            " x ",
            " bootleg",
        ]

        return markers.contains { title.contains($0) }
    }

    /// Pure title-gate decision, extracted so it stays testable (see `_selfCheck`).
    /// Rejects a candidate that shares no title token with the source and is not a
    /// substring match either way — i.e. a different song that only shares the artist.
    nonisolated static func titleGateRejects(
        sourceTitle: String,
        candidateTitle: String,
        titleOverlap: Double
    ) -> Bool {
        guard !sourceTitle.isEmpty else { return false }
        guard titleOverlap == 0 else { return false }
        return !candidateTitle.contains(sourceTitle) && !sourceTitle.contains(candidateTitle)
    }

    #if DEBUG
    /// One runnable check for the title gate. Fails loudly if the logic breaks.
    nonisolated static func _selfCheck() {
        // Reported bug: same artist, different song → rejected.
        assert(titleGateRejects(sourceTitle: "ik kudi acoustic", candidateTitle: "dooron dooron", titleOverlap: 0) == true)
        // Correct match with shared tokens → allowed.
        assert(titleGateRejects(sourceTitle: "ik kudi acoustic", candidateTitle: "ik kudi", titleOverlap: 0.5) == false)
        // Exact title → allowed.
        assert(titleGateRejects(sourceTitle: "rock with you", candidateTitle: "rock with you", titleOverlap: 1) == false)
        // Substring containment with 0 Jaccard (candidate wraps source) → allowed.
        assert(titleGateRejects(sourceTitle: "faasle", candidateTitle: "faasle official video", titleOverlap: 0) == false)
        // Empty source title → never gate (nothing to compare).
        assert(titleGateRejects(sourceTitle: "", candidateTitle: "anything", titleOverlap: 0) == false)
    }
    #endif
}
