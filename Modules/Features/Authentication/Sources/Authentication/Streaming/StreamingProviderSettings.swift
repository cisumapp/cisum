import Foundation
import Observation

@Observable
@MainActor
public final class StreamingProviderSettings {
    public static let shared = StreamingProviderSettings()

    private enum Keys {
        static let spotifyClientID = "streaming.spotify.client_id"
        static let spotifyClientSecret = "streaming.spotify.client_secret"
        static let spotifyPreferAnonymousFallback = "streaming.spotify.prefer_anonymous_fallback"
    }

    /// Read off the main actor (import manager, SpotifySDK), so they're plain nonisolated keys.
    public nonisolated static let spotifySyncLikedSongsKey = "streaming.spotify.sync_liked_songs"
    /// SpotifySDK reads this same key before every library write (SpotifyPathfinderClient+LibraryWrites).
    public nonisolated static let spotifyAllowWritesKey = "SpotifySDK.writesEnabled"

    private let defaults: UserDefaults

    public var spotifyClientID: String {
        didSet {
            defaults.set(spotifyClientID, forKey: Keys.spotifyClientID)
        }
    }

    public var spotifyClientSecret: String {
        didSet {
            defaults.set(spotifyClientSecret, forKey: Keys.spotifyClientSecret)
        }
    }

    public var spotifyPreferAnonymousFallback: Bool {
        didSet {
            defaults.set(spotifyPreferAnonymousFallback, forKey: Keys.spotifyPreferAnonymousFallback)
        }
    }

    /// Keep a read-only copy of Spotify Liked Songs in the library, refreshed on launch/foreground.
    public var spotifySyncLikedSongs: Bool {
        didSet {
            defaults.set(spotifySyncLikedSongs, forKey: Self.spotifySyncLikedSongsKey)
        }
    }

    /// Lets cisum change the Spotify account (like, follow, edit playlists). Off by default.
    public var spotifyAllowWrites: Bool {
        didSet {
            defaults.set(spotifyAllowWrites, forKey: Self.spotifyAllowWritesKey)
        }
    }

    public var hasSpotifyCredentials: Bool {
        !spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var spotifyModeLabel: String {
        hasSpotifyCredentials ? "Official" : "Anonymous Fallback"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        self.spotifyClientSecret = defaults.string(forKey: Keys.spotifyClientSecret) ?? ""
        self.spotifyPreferAnonymousFallback = defaults.object(forKey: Keys.spotifyPreferAnonymousFallback) as? Bool ?? true
        self.spotifySyncLikedSongs = defaults.bool(forKey: Self.spotifySyncLikedSongsKey)
        self.spotifyAllowWrites = defaults.bool(forKey: Self.spotifyAllowWritesKey)
    }

    public func clearSpotifyCredentials() {
        spotifyClientID = ""
        spotifyClientSecret = ""
    }
}
