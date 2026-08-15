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

    /// Records a successful resolution.
    ///
    /// Binds the song to this service when it is a library track, and caches the stream URL when
    /// the service permits caching. An ad-hoc play — a search result with no `songID` — is not
    /// persisted, because there is no canonical song to hang the binding from; adding the track to
    /// the library is what makes it cheap next time.
    public func persist(_ ref: PlayableRef, track: SourceTrack, stream: SourceStream) {
        guard let songID = ref.songID else { return }

        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.songID == songID })
        descriptor.fetchLimit = 1

        do {
            guard let song = try context.fetch(descriptor).first else { return }

            let binding = song.bind(
                sourceID: ref.sourceID,
                sourceTrackID: track.id,
                isrc: track.isrc,
                durationSeconds: track.durationSeconds,
                audioQualityLabel: track.audioQualityLabel,
                allowsStreamCaching: stream.isCacheable
            )

            binding.cacheStream(
                url: stream.url,
                mimeType: stream.mimeType,
                expiresAt: stream.expiresAt,
                headers: stream.headers,
                defaultLifetime: defaultStreamLifetime
            )

            try context.save()
        } catch {
            PerfLog.error("Could not persist SongSource for \(ref.sourceID): \(error)")
        }
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
