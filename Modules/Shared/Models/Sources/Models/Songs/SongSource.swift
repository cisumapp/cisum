//
//  SongSource.swift
//  Models
//
//  One provider's representation of a canonical Song — and the cached stream that goes with it.
//

import Foundation
import SwiftData

/// How one music service represents a canonical `Song`.
///
/// This replaces the wide-column approach, where `Song` carried a hardcoded property per provider
/// (`spotifyTrackID`, `youtubeVideoID`, `tidalID`, `qobuzID`, `soundcloudID`, `deezerID`,
/// `appleMusicSongID`). That could never represent a user-installed plugin: a plugin cannot be
/// given a column, and the closed `MediaProvider` enum could not be given a case.
///
/// **`sourceID` is an open `String` for exactly that reason.** `"spotify"`, `"youtube"`, and
/// `"tidals-morgk"` are all equally valid, and a plugin cisum has never heard of becomes a
/// first-class identity source with no schema change.
@Model
public final class SongSource {
    /// Which service this representation belongs to. An open string, never an enum.
    public var sourceID: String

    /// This service's identifier for the track. **Opaque — never parse it.**
    ///
    /// Only meaningful paired with `sourceID`; IDs are not portable between services. Some are
    /// session-scoped: two known modules mint an anonymous token at load time and embed it in
    /// every track ID, so a stored value can stop resolving between launches. Treat it as a
    /// **hint that may fail** — on failure, re-match rather than surfacing an error.
    public var sourceTrackID: String

    /// What this service claims about the track, kept as evidence for reconciliation.
    public var isrc: String?
    public var durationSeconds: Double?
    public var artworkURLString: String?

    /// The service's own quality label, e.g. `"FLAC 16-bit / 44.1 kHz"`. **Display only.**
    ///
    /// There is no shared vocabulary across services — one returns prose, another returns the bare
    /// enum `"LOSSLESS"`, another `"320kbps"`. Never switch on this.
    public var audioQualityLabel: String?

    // MARK: Stream cache
    //
    // This is what makes replay cheap. On the second play of a song there is no search, and if the
    // URL is still fresh there is no network call at all.

    /// The last resolved stream URL, if it may be cached.
    public var cachedStreamURLString: String?

    /// When `cachedStreamURLString` was obtained.
    public var cachedStreamResolvedAt: Date?

    /// When it stops working.
    ///
    /// **Never nil while a URL is cached.** A stream URL is a runtime artifact with a short life —
    /// YouTube `googlevideo` URLs last about six hours, Tidal and Qobuz CDN tokens less. Caching
    /// one without an expiry guarantees a future playback failure. When a service reports no
    /// expiry, the store applies a conservative default rather than treating it as permanent.
    public var cachedStreamExpiresAt: Date?

    public var cachedStreamMIMEType: String?

    /// Whether this service's URLs may be cached at all.
    ///
    /// Some modules declare `noStreamCache` because their URLs are single-use or session-bound.
    /// For those, every play resolves fresh.
    public var allowsStreamCaching: Bool

    /// When this binding was last confirmed to work, for pruning stale representations.
    public var lastVerifiedAt: Date?

    public var createdAt: Date

    /// The canonical song this represents.
    @Relationship(inverse: \Song.sources)
    public var song: Song?

    public init(
        sourceID: String,
        sourceTrackID: String,
        isrc: String? = nil,
        durationSeconds: Double? = nil,
        artworkURLString: String? = nil,
        audioQualityLabel: String? = nil,
        allowsStreamCaching: Bool = true,
        lastVerifiedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.sourceID = sourceID
        self.sourceTrackID = sourceTrackID
        self.isrc = isrc
        self.durationSeconds = durationSeconds
        self.artworkURLString = artworkURLString
        self.audioQualityLabel = audioQualityLabel
        self.allowsStreamCaching = allowsStreamCaching
        self.lastVerifiedAt = lastVerifiedAt
        self.createdAt = createdAt
    }

    // MARK: - Stream cache access

    /// The cached stream URL, but only if it is still usable.
    ///
    /// Returns `nil` when caching is disallowed, nothing is cached, or the URL has expired —
    /// so a caller can treat a non-nil result as "play this now, no network needed".
    public func freshStreamURL(at date: Date = .now) -> URL? {
        guard allowsStreamCaching,
              let urlString = cachedStreamURLString,
              let expiresAt = cachedStreamExpiresAt,
              expiresAt > date,
              let url = URL(string: urlString)
        else { return nil }
        return url
    }

    /// Records a resolved stream.
    ///
    /// - Parameter expiresAt: The service's declared expiry. When `nil`, `defaultLifetime` applies
    ///   from now — unknown means "assume short", not "assume permanent".
    /// - Parameter defaultLifetime: One hour by default, comfortably inside the shortest observed
    ///   provider expiry.
    public func cacheStream(
        url: URL,
        mimeType: String?,
        expiresAt: Date?,
        defaultLifetime: TimeInterval = 3600,
        now: Date = .now
    ) {
        guard allowsStreamCaching else { return }
        cachedStreamURLString = url.absoluteString
        cachedStreamMIMEType = mimeType
        cachedStreamResolvedAt = now
        cachedStreamExpiresAt = expiresAt ?? now.addingTimeInterval(defaultLifetime)
        lastVerifiedAt = now
    }

    /// Discards the cached URL after a playback failure, forcing a fresh resolve next time.
    public func invalidateStream() {
        cachedStreamURLString = nil
        cachedStreamResolvedAt = nil
        cachedStreamExpiresAt = nil
        cachedStreamMIMEType = nil
    }
}
