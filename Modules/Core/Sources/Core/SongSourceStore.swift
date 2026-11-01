//
//  SongSourceStore.swift
//  Core
//
//  The persistence half of "match once, then never search again".
//

import Foundation
import Models
import ProviderSDK
import SwiftData
import Utilities

/// Persists the binding between a canonical `Song` and one service's track, plus the cached
/// stream URL for it.
///
/// Player deliberately does not import SwiftData — persistence is an application decision — so it
/// asks three questions through closures and this answers them:
///
/// - *What do I already know about this ref?* → `lookup`
/// - *Remember this, so I never have to search again* → `persist`
/// - *That URL is dead, forget it* → `invalidate`
///
/// Without the `persist` half, matching would rerun on every play and the whole point of the reset
/// would be lost, so this type is load-bearing despite being small.
@MainActor
public final class SongSourceStore {
    private let context: ModelContext

    /// How long a stream URL is trusted when the service does not say.
    ///
    /// One hour is comfortably inside the shortest observed provider expiry. Guessing long is the
    /// dangerous direction: it produces a playback failure the user sees, whereas guessing short
    /// costs one cheap re-resolve.
    private let defaultStreamLifetime: TimeInterval = 3600

    public init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
    }

    /// The stored representation for a ref, if there is one.
    public func lookup(_ ref: PlayableRef) -> SongSource? {
        let sourceID = ref.sourceID
        let trackID = ref.sourceTrackID

        var descriptor = FetchDescriptor<SongSource>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.sourceTrackID == trackID }
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            PerfLog.error("SongSource lookup failed for \(sourceID)/\(trackID): \(error)")
            return nil
        }
    }

    /// Every stored representation cisum has of this ref's track, **across providers**.
    ///
    /// The ref's own source first, then the rest ordered by source id, so the caller's candidate set
    /// — and therefore the ranking's final tie-break — is deterministic.
    ///
    /// This is what lets a second provider compete for the same recording at all. A row is only
    /// included when it is a real statement about *this* recording: either the ref's own binding
    /// (matched by `(sourceID, sourceTrackID)`, so it is the same track by construction) or a row
    /// reached through the canonical `Song`, whose link was established by the identity layer rather
    /// than by anything the resolver inferred.
    ///
    /// One representation per provider. A provider can legitimately hold two rows for a recording
    /// (a re-upload, say), but they are the same provider's opinion of the same audio, and offering
    /// both as candidates would spend a resolve on each without adding a distinct stream.
    public func knownRepresentations(for ref: PlayableRef) -> [SongSource] {
        var found: [SongSource] = []
        var seen = Set<String>()

        if let own = lookup(ref) {
            found.append(own)
            seen.insert(own.sourceID)
        }

        if let songID = ref.songID, let song = fetchSong(songID) {
            let others = song.sources
                .filter { !seen.contains($0.sourceID) }
                .sorted { $0.sourceID < $1.sourceID }
            found.append(contentsOf: others)
        }

        return found
    }

    /// Records a successful resolution.
    ///
    /// Persists the provider binding and caches the stream URL when the service permits caching.
    ///
    /// **A binding does not require a canonical `Song`.** An ad-hoc play — a search result with no
    /// `songID` — persists an orphan `SongSource` (`song == nil`) keyed by
    /// `(sourceID, sourceTrackID)`, so the next play of that result is a lookup rather than a fresh
    /// resolve. No `Song` is fabricated: canonical identity is established only when a `songID`
    /// resolves to a real record.
    public func persist(_ ref: PlayableRef, track: SourceTrack, stream: SourceStream) {
        let existing = fetchBinding(sourceID: ref.sourceID, sourceTrackID: track.id)
        let resolvedSongID = ref.songID.flatMap { fetchSong($0) }?.songID

        let binding: SongSource
        switch ProviderBindingPolicy.action(
            existingBindingFound: existing != nil,
            resolvedSongID: resolvedSongID
        ) {
        case .updateExisting:
            // Reuse in place. Creating a second row for the same key would make lookups ambiguous
            // and defeat the warm path the binding exists for.
            guard let existing else { return }
            existing.updateEvidence(
                isrc: track.isrc,
                durationSeconds: track.durationSeconds,
                audioQualityLabel: track.audioQualityLabel,
                allowsStreamCaching: stream.isCacheable
            )
            // Promote an orphan to canonical only when identity is now legitimately known.
            if existing.song == nil, let songID = resolvedSongID, let song = fetchSong(songID) {
                existing.song = song
            }
            binding = existing

        case let .bindToSong(songID):
            guard let song = fetchSong(songID) else { return }
            binding = song.bind(
                sourceID: ref.sourceID,
                sourceTrackID: track.id,
                isrc: track.isrc,
                durationSeconds: track.durationSeconds,
                audioQualityLabel: track.audioQualityLabel,
                allowsStreamCaching: stream.isCacheable
            )

        case .createOrphan:
            // Ad-hoc: persist the representation on its own, with no canonical song.
            let orphan = SongSource(sourceID: ref.sourceID, sourceTrackID: track.id)
            orphan.updateEvidence(
                isrc: track.isrc,
                durationSeconds: track.durationSeconds,
                audioQualityLabel: track.audioQualityLabel,
                allowsStreamCaching: stream.isCacheable
            )
            context.insert(orphan)
            binding = orphan
        }

        binding.cacheStream(
            url: stream.url,
            mimeType: stream.mimeType,
            expiresAt: stream.expiresAt,
            headers: stream.headers,
            defaultLifetime: defaultStreamLifetime
        )

        save()
    }

    /// The stored representation for a provider id pair, if one exists.
    private func fetchBinding(sourceID: String, sourceTrackID: String) -> SongSource? {
        var descriptor = FetchDescriptor<SongSource>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.sourceTrackID == sourceTrackID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchSong(_ songID: String) -> Song? {
        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.songID == songID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            PerfLog.error("Could not persist SongSource: \(error)")
        }
    }

    /// Forgets every YouTube binding the pre-official-audio matcher chose by search.
    ///
    /// Which rows qualify is `ProviderBindingPolicy.isSearchMatchedYouTubeBinding`. Orphans are left
    /// alone: with no song there is nothing they were matched *for*.
    ///
    /// - Returns: How many bindings were removed.
    @discardableResult
    public func resetSearchMatchedYouTubeBindings() -> Int {
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        var removed = 0
        for song in songs {
            let sourceIDs = song.sources.map(\.sourceID)
            for source in song.sources where ProviderBindingPolicy.isSearchMatchedYouTubeBinding(
                sourceID: source.sourceID,
                siblingSourceIDs: sourceIDs
            ) {
                context.delete(source)
                removed += 1
            }
        }
        if removed > 0 {
            save()
        }
        PerfLog.info("SongSourceStore: reset \(removed) search-matched YouTube binding(s)")
        return removed
    }

    /// Drops a cached URL after playback failed with it.
    ///
    /// The binding itself survives — a dead CDN URL says nothing about whether the track id is
    /// still correct, and throwing away the binding would force a needless re-match.
    public func invalidate(_ ref: PlayableRef) {
        guard let source = lookup(ref) else { return }
        source.invalidateStream()
        try? context.save()
    }
}
