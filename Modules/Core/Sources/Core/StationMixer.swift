//
//  StationMixer.swift
//  Core
//
//  The endless queue: one station drawn from every service that has an opinion about the seed.
//

import Foundation
import Models
import Player
import Utilities
import YouTubeSDK
#if canImport(SpotifySDK)
import Authentication
import SpotifySDK
#endif

/// Builds a song station from several services at once, one page per refill.
///
/// Each page asks every available source concurrently and interleaves their picks, so the queue
/// is not one service's fixed radio for one song:
///
/// - **YouTube Music** — the seed's own radio (`RDAMVM<id>`), paged by its continuation.
/// - **Spotify** — the recommendation engine, which scores candidates against the user's own top
///   artists and tracks. Each later page is seeded by one of Spotify's previous picks, so the
///   station drifts outward instead of circling the first song. Only when a Spotify session exists.
/// - **Your music** — the user's own listening: YouTube Music liked songs and history, Spotify liked
///   songs and top tracks, from whichever of the two is signed in. Each page mixes in the user's
///   tracks by artists already on the station, or a couple of favourites when none are.
///
/// Picks are plain `PlayableRef`s: a Spotify pick plays through the same resolver as a tapped
/// Spotify search result. Duplicates — across sources and across pages — are dropped by song
/// identity (`PlaybackQueue.songKey`), as is the seed itself, which YouTube likes to lead with.
///
/// The station is keyed by its seed: a new seed, or a fresh request (`continuation == nil`), starts
/// a new station.
@MainActor
final class StationMixer {
    private let youtube: YouTube
    /// The seed's YouTube video id: its own for a YouTube ref, otherwise the persisted binding.
    private let youtubeVideoID: @MainActor (PlayableRef) -> String?

    private var seedKey: String?
    private var seen = Set<String>()
    private var youtubeContinuation: String?
    private var youtubeDone = false
    private var spotifyDriftSeeds: [PlayableRef] = []

    /// The user's own tracks across signed-in services, refreshed every `profileLifetime`.
    private var profile: [PlayableRef] = []
    private var profileLoadedAt: Date?
    private static let profileLifetime: TimeInterval = 30 * 60

    init(youtube: YouTube, youtubeVideoID: @escaping @MainActor (PlayableRef) -> String?) {
        self.youtube = youtube
        self.youtubeVideoID = youtubeVideoID
    }

    /// The station's next page. The continuation is opaque to the caller: non-nil while any source
    /// can produce more, which with Spotify's drift is indefinitely.
    func nextPage(seed: PlayableRef, continuation: String?) async -> RadioBatch? {
        let key = "\(seed.sourceID):\(seed.sourceTrackID)"
        if continuation == nil || key != seedKey {
            seedKey = key
            seen = [PlaybackQueue.songKey(seed)]
            youtubeContinuation = nil
            youtubeDone = false
            spotifyDriftSeeds = []
        }

        async let youtubePicks = youtubePage(seed: seed)
        async let spotifyPicks = spotifyPage(seed: seed)
        async let profileReady: Void = loadProfileIfNeeded()
        let (fromYouTube, fromSpotify, _) = await (youtubePicks, spotifyPicks, profileReady)

        // Alternate the sources so neither dominates the next stretch of the queue.
        var interleaved: [PlayableRef] = []
        for index in 0 ..< max(fromYouTube.count, fromSpotify.count) {
            if index < fromYouTube.count { interleaved.append(fromYouTube[index]) }
            if index < fromSpotify.count { interleaved.append(fromSpotify[index]) }
        }

        // The user's own tracks, one every four, so the station sounds like them and not just the seed.
        let yours = yourPicks(stationArtists: Set(([seed] + interleaved).map(Self.artistKey)))
        var mixed: [PlayableRef] = []
        var pending = yours[...]
        for (index, ref) in interleaved.enumerated() {
            mixed.append(ref)
            if index % 4 == 3, let next = pending.popFirst() { mixed.append(next) }
        }
        mixed.append(contentsOf: pending)
        let fresh = mixed.filter { ref in
            !seed.title.localizedCaseInsensitiveContains(ref.title) || !sameArtist(ref, seed)
        }
        .filter { seen.insert(PlaybackQueue.songKey($0)).inserted }

        PerfLog.info("StationMixer: '\(seed.title)' → YouTube \(fromYouTube.count), Spotify \(fromSpotify.count), yours \(yours.count) of \(profile.count), \(fresh.count) new")
        let hasMore = !youtubeDone || !spotifyDriftSeeds.isEmpty
        return RadioBatch(refs: fresh, continuation: hasMore ? "station" : nil)
    }

    private func sameArtist(_ lhs: PlayableRef, _ rhs: PlayableRef) -> Bool {
        Self.artistKey(lhs) == Self.artistKey(rhs)
    }

    /// The normalised primary artist, the same one `PlaybackQueue.songKey` identifies songs by.
    private static func artistKey(_ ref: PlayableRef) -> String {
        PlaybackQueue.songKey(ref).split(separator: "|").last.map(String.init) ?? ""
    }

    // MARK: - Your music

    /// Up to four of the user's tracks by artists already on the station; failing that, two
    /// favourites, so every page carries something familiar.
    private func yourPicks(stationArtists: Set<String>) -> [PlayableRef] {
        let unplayed = profile.filter { !seen.contains(PlaybackQueue.songKey($0)) }
        let related = unplayed.filter { stationArtists.contains(Self.artistKey($0)) }.shuffled()
        return related.isEmpty ? Array(unplayed.shuffled().prefix(2)) : Array(related.prefix(4))
    }

    /// The user's listening across whichever services are signed in, fetched concurrently.
    private func loadProfileIfNeeded() async {
        if let profileLoadedAt, Date().timeIntervalSince(profileLoadedAt) < Self.profileLifetime { return }
        profileLoadedAt = Date()

        async let fromYouTube = youtubeProfile()
        async let fromSpotify = spotifyProfile()
        let (youtubeTracks, spotifyTracks) = await (fromYouTube, fromSpotify)
        var keys = Set<String>()
        profile = (youtubeTracks + spotifyTracks).filter { keys.insert(PlaybackQueue.songKey($0)).inserted }
        PerfLog.info("StationMixer: listening profile — YouTube Music \(youtubeTracks.count), Spotify \(spotifyTracks.count), \(profile.count) unique")
    }

    private func youtubeProfile() async -> [PlayableRef] {
        guard youtube.isAuthenticated else { return [] }
        async let liked = try? youtube.music.getLikedSongs()
        async let history = try? youtube.music.getHistory()
        let songs = await (liked ?? []) + (history ?? [])
        return songs.map(Self.ref(from:))
    }

    private func spotifyProfile() async -> [PlayableRef] {
        #if canImport(SpotifySDK)
        guard let sdk = SpotifySessionCoordinator.shared.sdk else { return [] }
        async let liked = try? sdk.account.likedSongs(offset: 0, limit: 50).items.map(\.track)
        async let top = try? sdk.restClient.fetchTopTracks(timeRange: "short_term", limit: 50)
        let tracks = await (top ?? []) + (liked ?? [])
        return tracks.map(Self.ref(from:))
        #else
        return []
        #endif
    }

    // MARK: - YouTube Music

    private func youtubePage(seed: PlayableRef) async -> [PlayableRef] {
        guard !youtubeDone, let videoID = youtubeVideoID(seed) else { return [] }
        do {
            let page = if let youtubeContinuation {
                try await youtube.music.getRadioContinuation(token: youtubeContinuation)
            } else {
                try await youtube.music.getRadio(videoId: videoID, playlistId: "RDAMVM\(videoID)")
            }
            youtubeContinuation = page.continuationToken
            youtubeDone = page.continuationToken == nil
            return page.items
                .filter { $0.videoId != videoID }
                .map(Self.ref(from:))
        } catch {
            PerfLog.warning("StationMixer: YouTube radio failed for '\(seed.title)': \(error.localizedDescription)")
            youtubeDone = true
            return []
        }
    }

    // MARK: - Spotify

    private func spotifyPage(seed: PlayableRef) async -> [PlayableRef] {
        #if canImport(SpotifySDK)
        guard let sdk = SpotifySessionCoordinator.shared.sdk else { return [] }
        let anchor = spotifyDriftSeeds.randomElement() ?? seed
        do {
            guard let anchorTrack = try await sdk.search.search("\(anchor.title) \(anchor.artist)", limit: 1)
                .tracks?.items.first
            else { return [] }
            let picks = try await sdk.recommendations.generateRecommendations(for: anchorTrack, limit: 20)
                .map(Self.ref(from:))
            spotifyDriftSeeds = picks
            return picks
        } catch {
            PerfLog.warning("StationMixer: Spotify recommendations failed for '\(anchor.title)': \(error.localizedDescription)")
            return []
        }
        #else
        return []
        #endif
    }

    // MARK: - Mapping

    private static func ref(from song: YouTubeMusicSong) -> PlayableRef {
        PlayableRef(
            songID: nil,
            sourceID: "youtube_music",
            sourceTrackID: song.videoId,
            title: song.title,
            artist: song.artistsDisplay,
            artworkURL: song.thumbnailURL,
            durationSeconds: song.duration,
            album: song.album
        )
    }

    #if canImport(SpotifySDK)
    private static func ref(from track: SpotifyTrack) -> PlayableRef {
        PlayableRef(
            songID: nil,
            sourceID: "spotify",
            sourceTrackID: track.id,
            title: track.name,
            artist: track.artists.map(\.name).joined(separator: ", "),
            artworkURL: track.album?.images.first?.url,
            durationSeconds: Double(track.durationMS) / 1000,
            isrc: track.isrc,
            album: track.album?.name
        )
    }
    #endif
}
