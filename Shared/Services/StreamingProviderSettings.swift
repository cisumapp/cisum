import Foundation
import Observation

#if canImport(TidalKit)
import TidalKit
#endif

@Observable
@MainActor
final class StreamingProviderSettings {
    static let shared = StreamingProviderSettings()

    private enum Keys {
        static let spotifyClientID = "streaming.spotify.client_id"
        static let spotifyClientSecret = "streaming.spotify.client_secret"
        static let spotifyPreferAnonymousFallback = "streaming.spotify.prefer_anonymous_fallback"
        static let tidalPreferredQuality = "streaming.tidal.preferred_quality"
    }

    private let defaults: UserDefaults

    var spotifyClientID: String {
        didSet {
            defaults.set(spotifyClientID, forKey: Keys.spotifyClientID)
        }
    }

    var spotifyClientSecret: String {
        didSet {
            defaults.set(spotifyClientSecret, forKey: Keys.spotifyClientSecret)
        }
    }

    var spotifyPreferAnonymousFallback: Bool {
        didSet {
            defaults.set(spotifyPreferAnonymousFallback, forKey: Keys.spotifyPreferAnonymousFallback)
        }
    }

    var tidalPreferredQualityRawValue: String {
        didSet {
            defaults.set(tidalPreferredQualityRawValue, forKey: Keys.tidalPreferredQuality)
        }
    }

    var hasSpotifyCredentials: Bool {
        !spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var spotifyModeLabel: String {
        hasSpotifyCredentials ? "Official" : "Anonymous Fallback"
    }

#if canImport(TidalKit)
    var tidalPreferredQuality: MonochromeAudioQuality {
        get {
            MonochromeAudioQuality(rawValue: tidalPreferredQualityRawValue) ?? .hiResLossless
        }
        set {
            tidalPreferredQualityRawValue = newValue.rawValue
        }
    }

    var tidalPreferredQualityLabel: String {
        tidalPreferredQuality.label
    }
#else
    var tidalPreferredQualityLabel: String {
        tidalPreferredQualityRawValue
    }
#endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        self.spotifyClientSecret = defaults.string(forKey: Keys.spotifyClientSecret) ?? ""
        self.spotifyPreferAnonymousFallback = defaults.object(forKey: Keys.spotifyPreferAnonymousFallback) as? Bool ?? true
        self.tidalPreferredQualityRawValue = defaults.string(forKey: Keys.tidalPreferredQuality) ?? "HI_RES_LOSSLESS"
    }

    func clearSpotifyCredentials() {
        spotifyClientID = ""
        spotifyClientSecret = ""
    }
}
