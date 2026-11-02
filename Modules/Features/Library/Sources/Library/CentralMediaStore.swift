import Foundation
import Models
import SwiftData
import SwiftUI
import Utilities

#if canImport(SpotifySDK)
import SpotifySDK
#endif

@ModelActor
public actor CentralMediaStore {
    public struct ArtistSnapshot: Sendable {
        public let displayName: String
        public let normalizedName: String
        public let artworkURLString: String?
        public let genres: [String]
        public let spotifyArtistID: String?
        public let spotifyArtistURI: String?
        public let youtubeChannelID: String?
        public let youtubeMusicBrowseID: String?
        public let appleMusicArtistID: String?

        public init(displayName: String, normalizedName: String, artworkURLString: String?, genres: [String], spotifyArtistID: String?, spotifyArtistURI: String?, youtubeChannelID: String?, youtubeMusicBrowseID: String?, appleMusicArtistID: String?) {
            self.displayName = displayName
            self.normalizedName = normalizedName
            self.artworkURLString = artworkURLString
            self.genres = genres
            self.spotifyArtistID = spotifyArtistID
            self.spotifyArtistURI = spotifyArtistURI
            self.youtubeChannelID = youtubeChannelID
            self.youtubeMusicBrowseID = youtubeMusicBrowseID
            self.appleMusicArtistID = appleMusicArtistID
        }
    }

    public struct AlbumSnapshot: Sendable {
        public let title: String
        public let normalizedTitle: String
        public let primaryArtistName: String?
        public let primaryArtistID: String?
        public let artworkURLString: String?
        public let releaseDateString: String?
        public let totalTracks: Int?
        public let spotifyAlbumID: String?
        public let spotifyAlbumURI: String?
        public let youtubePlaylistID: String?
        public let appleMusicAlbumID: String?

        public init(title: String, normalizedTitle: String, primaryArtistName: String?, primaryArtistID: String?, artworkURLString: String?, releaseDateString: String?, totalTracks: Int?, spotifyAlbumID: String?, spotifyAlbumURI: String?, youtubePlaylistID: String?, appleMusicAlbumID: String?) {
            self.title = title
            self.normalizedTitle = normalizedTitle
            self.primaryArtistName = primaryArtistName
            self.primaryArtistID = primaryArtistID
            self.artworkURLString = artworkURLString
            self.releaseDateString = releaseDateString
            self.totalTracks = totalTracks
            self.spotifyAlbumID = spotifyAlbumID
            self.spotifyAlbumURI = spotifyAlbumURI
            self.youtubePlaylistID = youtubePlaylistID
            self.appleMusicAlbumID = appleMusicAlbumID
        }
    }

    public struct SongSnapshot: Sendable {
        public let title: String
        public let normalizedTitle: String
        public let primaryArtistName: String?
        public let primaryArtistID: String?
        public let albumTitle: String?
        public let albumID: String?
        public let durationSeconds: Double?
        public let artworkURLString: String?
        public let isExplicit: Bool
        public let providerFingerprint: String
        public let spotifyTrackID: String?
        public let spotifyTrackURI: String?
        public let spotifyPreviewURLString: String?
        public let youtubeVideoID: String?
        public let youtubeMusicVideoID: String?
        public let appleMusicSongID: String?

        public init(title: String, normalizedTitle: String, primaryArtistName: String?, primaryArtistID: String?, albumTitle: String?, albumID: String?, durationSeconds: Double?, artworkURLString: String?, isExplicit: Bool, providerFingerprint: String, spotifyTrackID: String?, spotifyTrackURI: String?, spotifyPreviewURLString: String?, youtubeVideoID: String?, youtubeMusicVideoID: String?, appleMusicSongID: String?) {
            self.title = title
            self.normalizedTitle = normalizedTitle
            self.primaryArtistName = primaryArtistName
            self.primaryArtistID = primaryArtistID
            self.albumTitle = albumTitle
            self.albumID = albumID
            self.durationSeconds = durationSeconds
            self.artworkURLString = artworkURLString
            self.isExplicit = isExplicit
            self.providerFingerprint = providerFingerprint
            self.spotifyTrackID = spotifyTrackID
            self.spotifyTrackURI = spotifyTrackURI
            self.spotifyPreviewURLString = spotifyPreviewURLString
            self.youtubeVideoID = youtubeVideoID
            self.youtubeMusicVideoID = youtubeMusicVideoID
            self.appleMusicSongID = appleMusicSongID
        }
    }

    @discardableResult
    public func upsertArtist(_ snapshot: ArtistSnapshot) -> String {
        let entry = existingArtist(for: snapshot) ?? Artist(
            displayName: snapshot.displayName,
            normalizedName: snapshot.normalizedName
        )

        if entry.modelContext == nil {
            modelContext.insert(entry)
        }

        entry.displayName = snapshot.displayName
        entry.normalizedName = snapshot.normalizedName
        entry.artworkURLString = snapshot.artworkURLString
        entry.genresJSONString = encodeStringArray(snapshot.genres)
        entry.spotifyArtistID = snapshot.spotifyArtistID
        entry.spotifyArtistURI = snapshot.spotifyArtistURI
        entry.youtubeChannelID = snapshot.youtubeChannelID
        entry.youtubeMusicBrowseID = snapshot.youtubeMusicBrowseID
        entry.appleMusicArtistID = snapshot.appleMusicArtistID
        entry.updatedAt = .now

        saveContext()
        return entry.artistID
    }

    @discardableResult
    public func upsertAlbum(_ snapshot: AlbumSnapshot) -> String {
        let entry = existingAlbum(for: snapshot) ?? Album(
            title: snapshot.title,
            normalizedTitle: snapshot.normalizedTitle
        )

        if entry.modelContext == nil {
            modelContext.insert(entry)
        }

        entry.title = snapshot.title
        entry.normalizedTitle = snapshot.normalizedTitle
        entry.primaryArtistName = snapshot.primaryArtistName
        entry.primaryArtistID = snapshot.primaryArtistID
        entry.artworkURLString = snapshot.artworkURLString
        entry.releaseDateString = snapshot.releaseDateString
        entry.totalTracks = snapshot.totalTracks
        entry.spotifyAlbumID = snapshot.spotifyAlbumID
        entry.spotifyAlbumURI = snapshot.spotifyAlbumURI
        entry.youtubePlaylistID = snapshot.youtubePlaylistID
        entry.appleMusicAlbumID = snapshot.appleMusicAlbumID
        entry.updatedAt = .now

        saveContext()
        return entry.albumID
    }

    @discardableResult
    public func upsertSong(_ snapshot: SongSnapshot) -> String {
        let entry = existingSong(for: snapshot) ?? Song(
            title: snapshot.title,
            normalizedTitle: snapshot.normalizedTitle,
            providerFingerprint: snapshot.providerFingerprint
        )

        if entry.modelContext == nil {
            modelContext.insert(entry)
        }

        entry.title = snapshot.title
        entry.normalizedTitle = snapshot.normalizedTitle
        entry.primaryArtistName = snapshot.primaryArtistName
        entry.primaryArtistID = snapshot.primaryArtistID
        entry.albumTitle = snapshot.albumTitle
        entry.albumID = snapshot.albumID
        entry.durationSeconds = snapshot.durationSeconds
        entry.artworkURLString = snapshot.artworkURLString
        entry.isExplicit = snapshot.isExplicit
        entry.providerFingerprint = snapshot.providerFingerprint

        // Provider ids become SongSource rows instead of columns on Song. `bind` is idempotent,
        // so re-importing the same track updates the existing row rather than duplicating it.
        let incoming: [(String, String?)] = [
            ("spotify", snapshot.spotifyTrackID),
            ("youtube", snapshot.youtubeVideoID),
            ("youtube_music", snapshot.youtubeMusicVideoID),
            ("apple_music", snapshot.appleMusicSongID),
        ]
        for (sourceID, trackID) in incoming {
            guard let trackID, !trackID.isEmpty else { continue }
            entry.bind(
                sourceID: sourceID,
                sourceTrackID: trackID,
                durationSeconds: snapshot.durationSeconds
            )
        }

        entry.updatedAt = .now

        saveContext()
        return entry.songID
    }

    public func songBySpotifyTrackID(_ spotifyTrackID: String) -> Song? {
        let trimmedID = spotifyTrackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        // Fetch the SongSource row and walk back to its song. The old version could query
        // Song directly because Spotify had its own column; with open-ended sources the
        // representation is the thing being looked up.
        var descriptor = FetchDescriptor<SongSource>(
            predicate: #Predicate { $0.sourceID == "spotify" && $0.sourceTrackID == trimmedID }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)?.song
    }

    /// Provider ids already known for a song, keyed by source.
    ///
    /// Replaces `ProviderIDsSnapshot`, which had one field per provider and so could not report
    /// anything about a user-installed plugin. A dictionary carries whatever the song actually has.
    public func cachedSourceIDs(forSpotifyTrackID spotifyTrackID: String) -> [String: String] {
        guard let song = songBySpotifyTrackID(spotifyTrackID) else { return [:] }
        return Dictionary(
            song.sources.map { ($0.sourceID, $0.sourceTrackID) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Records that a Spotify track is playable from another source.
    ///
    /// - Parameter sourceID: An open string, so a plugin works here exactly like a built-in
    ///   service does. The previous version switched over a closed `MediaProvider` enum with a
    ///   `default: break`, which silently discarded the result for anything it had no case for —
    ///   meaning a plugin could never have its playback target cached, and every play re-searched.
    public func cacheSpotifyPlaybackTarget(
        spotifyTrackID: String,
        mediaID: String,
        sourceID: String
    ) {
        guard let song = songBySpotifyTrackID(spotifyTrackID) else { return }
        song.bind(sourceID: sourceID, sourceTrackID: mediaID)
        song.lastResolvedAt = .now
        saveContext()
    }

    // MARK: - Canonical reconciliation (ISRC-first, library-wide dedup)

    /// Find-or-create the canonical `Song` for a neutral incoming track and merge its metadata.
    /// Returns the canonical `Song.songID`.
    ///
    /// Resolution follows `CanonicalIdentityPolicy` (U-11): established provider binding, then a
    /// **valid** matching ISRC, then confident `CanonicalSongReconciler` scoring. A title/artist
    /// fingerprint is never sufficient on its own.
    @discardableResult
    public func reconcile(_ incoming: IncomingTrack) -> String {
        let song = findCanonicalSong(for: incoming)
        merge(incoming, into: song)
        saveContext()
        return song.songID
    }

    /// Batch reconcile — used by the Download Manager per playlist page.
    @discardableResult
    public func reconcile(_ incoming: [IncomingTrack]) -> [String] {
        PerfLog.measure("reconcile-batch(\(incoming.count))") {
            incoming.map { reconcile($0) }
        }
    }

    private func findCanonicalSong(for t: IncomingTrack) -> Song {
        // 1. An established provider binding and a *valid* matching ISRC are gathered as evidence;
        //    the ordering between them (and confident scoring) is the frozen policy, not ad hoc.
        let established = existingSongByProviderID(t)?.songID

        let isrcMatch: String? = {
            guard let raw = t.isrc, CanonicalIdentityPolicy.isValidISRC(raw) else { return nil }
            return fetchFirstSong(predicate: #Predicate { $0.isrc == raw })?.songID
        }()

        let evidence = CanonicalIdentityPolicy.decide(
            isrc: t.isrc,
            establishedBinding: established,
            isrcMatch: isrcMatch,
            scoredMatches: scoredCandidates(
                title: t.title,
                artistName: t.artistName,
                durationSeconds: t.durationSeconds,
                albumName: t.albumName,
                versionEvidence: t.version
            )
        )

        if let match = song(for: evidence) {
            PerfLog.debug("reconcile matched songID=\(match.songID) via \(evidence)")
            return match
        }

        // 2. Create. Reached only when no candidate cleared the policy.
        let normalizedTitle = normalizedRankingText(t.title)
        let normalizedArtist = normalizedRankingText(t.artistName ?? "")
        let song = Song(
            title: t.title,
            normalizedTitle: normalizedTitle,
            providerFingerprint: makeProviderFingerprint(title: normalizedTitle, artist: normalizedArtist)
        )
        modelContext.insert(song)
        PerfLog.debug("reconcile created songID=\(song.songID) title=\(t.title)")
        return song
    }

    /// The canonical record the policy resolved to, if any.
    private func song(for evidence: CanonicalIdentityPolicy.Evidence) -> Song? {
        guard let songID = evidence.songID else { return nil }
        return fetchFirstSong(predicate: #Predicate { $0.songID == songID })
    }

    /// Scores existing canonical records for a title/artist/duration/album probe.
    ///
    /// The candidate pool is bounded by an exact artist match, so this is a small fetch rather
    /// than a full-table scan. When the artist is unknown there is no pool to score, and the
    /// conservative outcome is to keep the records separate.
    private func scoredCandidates(
        title: String,
        artistName: String?,
        durationSeconds: Double?,
        albumName: String?,
        versionEvidence: VersionEvidence? = nil
    ) -> [(songID: String, score: Double)] {
        guard let artist = artistName, !artist.isEmpty else { return [] }

        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.primaryArtistName == artist })
        descriptor.fetchLimit = 50
        let pool = (try? modelContext.fetch(descriptor)) ?? []

        return pool.compactMap { candidate in
            // The canonical side has no structured version column yet, so it carries only its raw
            // title — enough for the version gate's title-inference fallback, which is what runs.
            let key = SongMatchKey(
                songID: candidate.songID,
                normalizedTitle: CanonicalSongReconciler.normalize(candidate.title),
                artistName: candidate.primaryArtistName,
                durationSeconds: candidate.durationSeconds,
                albumName: candidate.albumTitle,
                title: candidate.title
            )
            let score = CanonicalSongReconciler.score(
                title: title,
                artistName: artistName,
                durationSeconds: durationSeconds,
                albumName: albumName,
                versionEvidence: versionEvidence,
                against: key
            )
            return score > 0 ? (songID: candidate.songID, score: score) : nil
        }
    }

    /// Finds an existing song by one provider's id for it.
    ///
    /// One query against `SongSource`, where the old version had a nine-case switch with a
    /// `default: return nil` — so an import from any provider not in that list silently created a
    /// duplicate song every time. `MediaProvider.rawValue` already matches the `sourceID`
    /// convention ("spotify", "youtube_music", …), and an id from a plugin works here too.
    private func existingSongByProviderID(_ t: IncomingTrack) -> Song? {
        let id = t.providerTrackID
        guard !id.isEmpty else { return nil }
        let sourceID = t.provider.rawValue

        var descriptor = FetchDescriptor<SongSource>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.sourceTrackID == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)?.song
    }

    private func merge(_ t: IncomingTrack, into song: Song) {
        // Union provider IDs + URIs + ISRC (never overwrite a known value with nil).
        unionProviderID(t, on: song)
        if song.isrc == nil, let isrc = t.isrc, !isrc.isEmpty {
            song.isrc = isrc
            song.isrcSourceID = t.provider.rawValue
        }

        // Scalar metadata: overwrite when the incoming provider is the new base, else gap-fill.
        // Which source's metadata wins. Provenance is now per field rather than one authoritative
        // provider per song, so this records where the title came from specifically.
        let currentBase: MediaProvider? = song.titleSourceID.flatMap { MediaProvider(rawValue: $0) }
        let newBase = CanonicalSongReconciler.mergedBaseProvider(current: currentBase, incoming: t.provider)
        if newBase == t.provider {
            song.title = t.title
            song.normalizedTitle = normalizedRankingText(t.title)
            if let a = t.artistName {
                song.primaryArtistName = a
            }
            if let al = t.albumName {
                song.albumTitle = al
            }
            if let d = t.durationSeconds {
                song.durationSeconds = d
            }
            if let art = t.artworkURLString {
                song.artworkURLString = art
            }
            song.isExplicit = t.isExplicit
            song.titleSourceID = t.provider.rawValue
        } else {
            if song.primaryArtistName == nil, let a = t.artistName {
                song.primaryArtistName = a
            }
            if song.albumTitle == nil, let al = t.albumName {
                song.albumTitle = al
            }
            if song.durationSeconds == nil, let d = t.durationSeconds {
                song.durationSeconds = d
            }
            if song.artworkURLString == nil, let art = t.artworkURLString {
                song.artworkURLString = art
                song.artworkSourceID = t.provider.rawValue
            }
        }
        song.titleSourceID = newBase.rawValue
        song.updatedAt = .now
    }

    /// Records the incoming provider's id for this song.
    ///
    /// `bind` is idempotent and handles both the new-row and update cases, so the nine-case
    /// switch this replaced is gone along with its `default: break` — which used to drop the id
    /// for any provider without a column.
    private func unionProviderID(_ t: IncomingTrack, on song: Song) {
        let id = t.providerTrackID
        guard !id.isEmpty else { return }

        song.bind(
            sourceID: t.provider.rawValue,
            sourceTrackID: id,
            isrc: t.isrc,
            durationSeconds: t.durationSeconds
        )
    }
}

#if canImport(SpotifySDK)
public extension CentralMediaStore {
    @discardableResult
    func upsertSpotifyArtist(_ artist: SpotifyArtist) -> String {
        let snapshot = ArtistSnapshot(
            displayName: artist.name,
            normalizedName: normalizedRankingText(artist.name),
            artworkURLString: artist.images.first?.url.absoluteString,
            genres: artist.genres,
            spotifyArtistID: artist.id,
            spotifyArtistURI: artist.uri,
            youtubeChannelID: nil,
            youtubeMusicBrowseID: nil,
            appleMusicArtistID: nil
        )

        return upsertArtist(snapshot)
    }

    @discardableResult
    func upsertSpotifyAlbum(_ album: SpotifyAlbum) -> String {
        let primaryArtist = album.artists.first
        let primaryArtistEntry = primaryArtist.map { upsertSpotifyArtist($0) }

        let snapshot = AlbumSnapshot(
            title: album.name,
            normalizedTitle: normalizedRankingText(album.name),
            primaryArtistName: primaryArtist?.name,
            primaryArtistID: primaryArtistEntry,
            artworkURLString: album.images.first?.url.absoluteString,
            releaseDateString: album.releaseDate,
            totalTracks: album.totalTracks,
            spotifyAlbumID: album.id,
            spotifyAlbumURI: album.uri,
            youtubePlaylistID: nil,
            appleMusicAlbumID: nil
        )

        return upsertAlbum(snapshot)
    }

    @discardableResult
    func upsertSpotifyTrack(_ track: SpotifyTrack) -> String {
        let primaryArtist = track.artists.first
        let primaryArtistEntry = primaryArtist.map { upsertSpotifyArtist($0) }
        let albumEntry = track.album.map { upsertSpotifyAlbum($0) }

        let normalizedTitle = normalizedRankingText(track.name)
        let normalizedArtist = normalizedRankingText(primaryArtist?.name ?? "")
        let fingerprint = makeProviderFingerprint(title: normalizedTitle, artist: normalizedArtist)

        let snapshot = SongSnapshot(
            title: track.name,
            normalizedTitle: normalizedTitle,
            primaryArtistName: primaryArtist?.name,
            primaryArtistID: primaryArtistEntry,
            albumTitle: track.album?.name,
            albumID: albumEntry,
            durationSeconds: TimeInterval(track.durationMS) / 1000,
            artworkURLString: track.album?.images.first?.url.absoluteString,
            isExplicit: track.isExplicit ?? false,
            providerFingerprint: fingerprint,
            spotifyTrackID: track.id,
            spotifyTrackURI: track.uri,
            spotifyPreviewURLString: track.previewURL?.absoluteString,
            youtubeVideoID: nil,
            youtubeMusicVideoID: nil,
            appleMusicSongID: nil
        )

        return upsertSong(snapshot)
    }

    @discardableResult
    func upsertSpotifyTracks(_ tracks: [SpotifyTrack]) -> [String] {
        tracks.map { upsertSpotifyTrack($0) }
    }

    @discardableResult
    func upsertSpotifyArtists(_ artists: [SpotifyArtist]) -> [String] {
        artists.map { upsertSpotifyArtist($0) }
    }

}
#endif

private extension CentralMediaStore {
    func existingArtist(for snapshot: ArtistSnapshot) -> Artist? {
        if let spotifyArtistID = snapshot.spotifyArtistID,
           let match = fetchFirstArtist(predicate: #Predicate { $0.spotifyArtistID == spotifyArtistID })
        {
            return match
        }

        if let youtubeChannelID = snapshot.youtubeChannelID,
           let match = fetchFirstArtist(predicate: #Predicate { $0.youtubeChannelID == youtubeChannelID })
        {
            return match
        }

        if let youtubeMusicBrowseID = snapshot.youtubeMusicBrowseID,
           let match = fetchFirstArtist(predicate: #Predicate { $0.youtubeMusicBrowseID == youtubeMusicBrowseID })
        {
            return match
        }

        if let appleMusicArtistID = snapshot.appleMusicArtistID,
           let match = fetchFirstArtist(predicate: #Predicate { $0.appleMusicArtistID == appleMusicArtistID })
        {
            return match
        }

        let normalizedName = snapshot.normalizedName
        return fetchFirstArtist(predicate: #Predicate { $0.normalizedName == normalizedName })
    }

    func existingAlbum(for snapshot: AlbumSnapshot) -> Album? {
        if let spotifyAlbumID = snapshot.spotifyAlbumID,
           let match = fetchFirstAlbum(predicate: #Predicate { $0.spotifyAlbumID == spotifyAlbumID })
        {
            return match
        }

        if let youtubePlaylistID = snapshot.youtubePlaylistID,
           let match = fetchFirstAlbum(predicate: #Predicate { $0.youtubePlaylistID == youtubePlaylistID })
        {
            return match
        }

        if let appleMusicAlbumID = snapshot.appleMusicAlbumID,
           let match = fetchFirstAlbum(predicate: #Predicate { $0.appleMusicAlbumID == appleMusicAlbumID })
        {
            return match
        }

        let normalizedTitle = snapshot.normalizedTitle
        return fetchFirstAlbum(predicate: #Predicate { $0.normalizedTitle == normalizedTitle })
    }

    func existingSong(for snapshot: SongSnapshot) -> Song? {
        // Any known provider id identifies the song, so this is one loop over the ids the snapshot
        // actually has rather than four hand-written blocks — and it extends to a plugin's id
        // without another block being added.
        let candidates: [(String, String?)] = [
            ("spotify", snapshot.spotifyTrackID),
            ("youtube", snapshot.youtubeVideoID),
            ("youtube_music", snapshot.youtubeMusicVideoID),
            ("apple_music", snapshot.appleMusicSongID),
        ]

        var establishedSongID: String?
        for (sourceID, trackID) in candidates {
            guard let trackID, !trackID.isEmpty else { continue }

            var descriptor = FetchDescriptor<SongSource>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.sourceTrackID == trackID }
            )
            descriptor.fetchLimit = 1

            if let match = (try? modelContext.fetch(descriptor).first)?.song {
                establishedSongID = match.songID
                break
            }
        }

        // A bare `providerFingerprint` (title|artist) match is deliberately NOT a merge path any
        // more (U-11). It has no duration or version check, so it merged distinct recordings. Only
        // confident scoring remains here; there is no ISRC on a `SongSnapshot`, and the snapshot's
        // provider ids are already covered by the established-binding loop above.
        let evidence = CanonicalIdentityPolicy.decide(
            isrc: nil,
            establishedBinding: establishedSongID,
            isrcMatch: nil,
            scoredMatches: scoredCandidates(
                title: snapshot.title,
                artistName: snapshot.primaryArtistName,
                durationSeconds: snapshot.durationSeconds,
                albumName: snapshot.albumTitle
            )
        )

        return song(for: evidence)
    }

    func fetchFirstArtist(predicate: Predicate<Artist>) -> Artist? {
        var descriptor = FetchDescriptor<Artist>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchFirstAlbum(predicate: Predicate<Album>) -> Album? {
        var descriptor = FetchDescriptor<Album>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchFirstSong(predicate: Predicate<Song>) -> Song? {
        var descriptor = FetchDescriptor<Song>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func saveContext() {
        try? modelContext.save()
    }

    func encodeStringArray(_ values: [String]) -> String? {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedValues.isEmpty else {
            return nil
        }

        guard let data = try? JSONEncoder().encode(cleanedValues) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func makeProviderFingerprint(title: String, artist: String) -> String {
        "\(title)|\(artist)"
    }
}

public extension EnvironmentValues {
    @Entry var centralMediaStore: CentralMediaStore?
}
