import Foundation
import Utilities
import YouTubeSDK

#if canImport(LyricsKit)
import LyricsKit
#endif

#if canImport(SpotifySDK)
import SpotifySDK
#endif

#if canImport(ProviderSDK)
import ProviderSDK
#endif

#if canImport(iTunesKit)
import iTunesKit
import Models
#endif

private let lyricsLog = CisumLog.playback
private let lyricsSP = CisumSignpost.playback

@MainActor
public final class LyricsAggregator {
    private let youtube: YouTube
    #if canImport(SpotifySDK)
    private var spicyLyricsClient: SpicyLyricsClient? {
        #if canImport(Services)
        guard let auth = SpotifySessionCoordinator.shared.sdk?.auth else { return nil }
        return SpicyLyricsClient(authService: auth)
        #else
        return nil
        #endif
    }
    #endif

    #if canImport(iTunesKit)
    private let itunesKit = iTunesKit()
    #endif

    public init(
        youtube: YouTube
    ) {
        self.youtube = youtube
    }

    public struct ResolvedLyrics {
        public let syncedLines: [TimedLyricLine]
        public let plainText: String?
        public let attribution: String?
    }

    public func fetchBestLyrics(
        title: String,
        artist: String,
        albumName: String?,
        durationHint: Int?,
        spotifyTrackId: String? = nil,
        youtubeVideoId _: String? = nil
    ) async throws -> ResolvedLyrics {
        let spid = lyricsSP.begin("fetch-lyrics", "title=\(title) artist=\(artist)")
        defer { lyricsSP.end("fetch-lyrics", state: spid, "title=\(title)") }

        // Priority 1: SpicyLyrics (Syllable-level sync if trackId available)
        #if canImport(SpotifySDK)
        if let trackId = spotifyTrackId, let spicyClient = spicyLyricsClient {
            lyricsLog.debug("Attempting SpicyLyrics for id=\(trackId, privacy: .public)")
            let spicySpid = lyricsSP.begin("fetch-spicy-lyrics", "id=\(trackId)")
            do {
                if let spicyLines = try await spicyClient.fetchLyrics(trackId: trackId), !spicyLines.isEmpty {
                    lyricsSP.end("fetch-spicy-lyrics", state: spicySpid, "id=\(trackId) success=true")
                    // Map SpicyLyricLine to TimedLyricLine
                    let timedLines = spicyLines.map { sl in
                        let mappedSyllables = sl.syllables.map { syl in
                            LyricSyllable(
                                text: syl.text,
                                timestamp: syl.timestamp,
                                endTime: syl.endTime,
                                isPartOfWord: syl.isPartOfWord
                            )
                        }
                        return TimedLyricLine(
                            timestamp: sl.timestamp,
                            text: sl.text,
                            syllables: mappedSyllables
                        )
                    }
                    return ResolvedLyrics(syncedLines: timedLines, plainText: nil, attribution: "SpicyLyrics")
                }
                lyricsSP.end("fetch-spicy-lyrics", state: spicySpid, "id=\(trackId) success=false")
            } catch {
                lyricsSP.end("fetch-spicy-lyrics", state: spicySpid, "id=\(trackId) error=\(error.localizedDescription)")
                lyricsLog.warning("LyricsAggregator: SpicyLyrics failed - \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif

        // Priority 3: LRCLIB (Line-level sync)
        #if canImport(LyricsKit)
        do {
            let artistName = artist
            let album = albumName ?? "Single"
            let duration = durationHint ?? 0

            lyricsLog.debug("Attempting LRCLIB for title=\(title, privacy: .public) artist=\(artistName, privacy: .public)")
            let lrclibSpid = lyricsSP.begin("fetch-lrclib-lyrics", "title=\(title)")

            if duration > 0, let best = try await LyricsKit.shared.bestLyrics(trackName: title, artistName: artistName, albumName: album, durationInSeconds: duration) {
                lyricsSP.end("fetch-lrclib-lyrics", state: lrclibSpid, "title=\(title) source=best")
                let mapped = mapLRCLIBRecord(best)
                if !mapped.syncedLines.isEmpty || mapped.plainText != nil {
                    return mapped
                }
            }

            let syncedCandidates = try await LyricsKit.shared.searchSynced(trackName: title, artistName: artistName, albumName: albumName)
            if let syncedMatch = syncedCandidates.first {
                lyricsSP.end("fetch-lrclib-lyrics", state: lrclibSpid, "title=\(title) source=searchSynced")
                let mapped = mapLRCLIBRecord(syncedMatch)
                if !mapped.syncedLines.isEmpty || mapped.plainText != nil {
                    return mapped
                }
            }
            lyricsSP.end("fetch-lrclib-lyrics", state: lrclibSpid, "title=\(title) success=false")
        } catch {
            lyricsLog.warning("LyricsAggregator: LRCLIB failed - \(error.localizedDescription, privacy: .public)")
        }
        #endif

        // Priority 4: YouTube SDK (Plain text)
        // YouTube typically returns plain text lyrics for a given browseId (which we don't have unless we fetch it from videoId).
        // If youtubeVideoId is available, we could fetch it via YouTubeMusicClient+Social...

        // Return empty if all fail
        return ResolvedLyrics(syncedLines: [], plainText: nil, attribution: nil)
    }

    #if canImport(LyricsKit)
    private func mapLRCLIBRecord(_ record: LyricsRecord) -> ResolvedLyrics {
        let syncedLines: [TimedLyricLine] = (record.parsedSyncedLyrics?.lines ?? [])
            .compactMap { line in
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TimedLyricLine(timestamp: line.timestamp, text: text)
            }

        var plainLyrics = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        if plainLyrics == nil || plainLyrics?.isEmpty == true {
            if record.instrumental { plainLyrics = "Instrumental" } else { plainLyrics = nil }
        }

        let attributionParts = [
            record.artistName.trimmingCharacters(in: .whitespacesAndNewlines),
            record.trackName.trimmingCharacters(in: .whitespacesAndNewlines),
        ].filter { !$0.isEmpty }

        let attribution = attributionParts.isEmpty ? nil : attributionParts.joined(separator: " • ")

        return ResolvedLyrics(
            syncedLines: syncedLines,
            plainText: plainLyrics,
            attribution: attribution
        )
    }
    #endif
}
