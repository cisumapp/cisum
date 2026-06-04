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
            case let .providerSDKTrack(track):
                track.isrc?.value
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

        let titleOverlap = tokenOverlapScore(normalizedSourceTitle, normalizedCandidateTitle)
        let artistOverlap = tokenOverlapScore(normalizedSourceArtist, normalizedCandidateArtist)
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
            + (0.26 * artistOverlap)
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
}
