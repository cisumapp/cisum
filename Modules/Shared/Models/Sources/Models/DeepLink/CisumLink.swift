import Foundation

/// Only http(s) artwork is portable — a local `file://` cache path is meaningless on another device.
private func remoteArtworkOnly(_ url: URL?) -> URL? {
    guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return nil
    }
    return url
}

// MARK: - Portable shared entities

/// A song reduced to portable, self-describing fields so it can be reconstructed on any device.
public struct SharedSong: Codable, Equatable, Sendable {
    public let provider: MediaProvider
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let durationSeconds: Double?
    public let isExplicit: Bool
    /// ISRC when known — lets a recipient match the same recording on Spotify/Apple Music.
    public let isrc: String?

    public init(provider: MediaProvider, id: String, title: String, artist: String, album: String? = nil, artworkURL: URL? = nil, durationSeconds: Double? = nil, isExplicit: Bool = false, isrc: String? = nil) {
        self.provider = provider
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = remoteArtworkOnly(artworkURL)
        self.durationSeconds = durationSeconds
        self.isExplicit = isExplicit
        self.isrc = isrc
    }

    /// YouTube Music songs load differently from plain YouTube videos.
    public var isMusic: Bool {
        provider == .youtubeMusic
    }
}

public extension SharedSong {
    /// Builds a shareable song from a neutral `SavableTrack`, choosing the provider from whichever
    /// provider id is present. Returns nil if the track has no shareable provider id.
    init?(savable: SavableTrack) {
        let provider: MediaProvider
        let id: String
        if let ytMusic = savable.youtubeMusicID {
            provider = .youtubeMusic; id = ytMusic
        } else if let yt = savable.youtubeID {
            provider = .youtube; id = yt
        } else if let spotify = savable.spotifyID {
            provider = .spotify; id = spotify
        } else {
            return nil
        }
        self.init(
            provider: provider,
            id: id,
            title: savable.title,
            artist: savable.artist,
            album: savable.album,
            artworkURL: savable.artworkURL,
            durationSeconds: savable.durationSeconds,
            isExplicit: savable.isExplicit
        )
    }
}

public enum SharedPlaylist: Equatable, Sendable {
    /// A provider-sourced playlist the recipient re-imports by (provider, sourceID).
    case imported(provider: MediaProvider, sourceID: String, name: String?)
    /// A cisum-local playlist whose tracklist travels inside the link.
    case embedded(name: String, author: String?, sharedBy: String?, tracks: [SharedSong])
    /// The web/shortened form: the payload lives server-side, referenced by a short `id`.
    /// The app resolves `id` → embedded/imported before importing.
    case shortened(id: String, name: String?, author: String?)

    public var displayName: String {
        switch self {
        case let .shortened(id, name, _): name ?? id
        case let .imported(_, sourceID, name): name ?? sourceID
        case let .embedded(name, _, _, _): name
        }
    }
}

public struct SharedArtist: Codable, Equatable, Sendable {
    public let provider: MediaProvider
    public let id: String
    public let name: String
    public let artworkURL: URL?

    public init(provider: MediaProvider, id: String, name: String, artworkURL: URL? = nil) {
        self.provider = provider
        self.id = id
        self.name = name
        self.artworkURL = remoteArtworkOnly(artworkURL)
    }
}

public struct SharedAlbum: Codable, Equatable, Sendable {
    public let provider: MediaProvider
    public let id: String
    public let name: String
    public let artworkURL: URL?

    public init(provider: MediaProvider, id: String, name: String, artworkURL: URL? = nil) {
        self.provider = provider
        self.id = id
        self.name = name
        self.artworkURL = remoteArtworkOnly(artworkURL)
    }
}

// MARK: - CisumLink

/// A shareable cisum deep link. `url()` builds `cisum://<entity>?…`; `parse(_:)` reverses it.
public enum CisumLink: Equatable, Sendable {
    case song(SharedSong)
    case playlist(SharedPlaylist)
    case artist(SharedArtist)
    case album(SharedAlbum)

    public static let scheme = "cisum"

    // Trust-boundary caps for the embedded-playlist blob (untrusted input).
    private static let maxDataParamChars = 64 * 1024 // reject huge links outright
    private static let maxInflatedBytes = 2 * 1024 * 1024 // decompression-bomb guard
    private static let maxEmbeddedTracks = 500

    // MARK: Build

    /// Universal-link host used when BUILDING links. Must be the host that serves the AASA without a
    /// redirect (Apple won't follow redirects) — `www` is canonical; the apex 307-redirects to it.
    public static let webHost = "www.cisum.studio"

    /// The `cisum://<entity>?…` custom-scheme form (works from Safari/Notes/QR).
    public func url() -> URL? {
        let (entity, items) = entityAndQuery()
        var comps = URLComponents()
        comps.scheme = Self.scheme
        comps.host = entity
        comps.queryItems = items
        return comps.url
    }

    /// The `https://cisum.studio/<entity>?…` Universal-Link form (tappable in chat apps).
    public func webURL() -> URL? {
        let (entity, items) = entityAndQuery()
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.webHost
        comps.path = "/\(entity)"
        comps.queryItems = items
        return comps.url
    }

    private func entityAndQuery() -> (entity: String, items: [URLQueryItem]) {
        switch self {
        case let .song(song):
            return ("song", Self.songQueryItems(song))
        case let .playlist(.imported(provider, sourceID, name)):
            return ("playlist", [
                URLQueryItem(name: "provider", value: provider.rawValue),
                URLQueryItem(name: "id", value: sourceID),
            ] + Self.optional("name", name))
        case let .playlist(.embedded(name, author, sharedBy, tracks)):
            var items = [URLQueryItem(name: "name", value: name)]
            items += Self.optional("author", author)
            items += Self.optional("sharedby", sharedBy)
            if let blob = Self.encodeTracks(tracks) {
                items.append(URLQueryItem(name: "data", value: blob))
            }
            return ("playlist", items)
        case let .playlist(.shortened(id, name, author)):
            return (
                "playlist",
                [URLQueryItem(name: "id", value: id)]
                    + Self.optional("name", name)
                    + Self.optional("author", author)
            )
        case let .artist(artist):
            return ("artist", [
                URLQueryItem(name: "provider", value: artist.provider.rawValue),
                URLQueryItem(name: "id", value: artist.id),
                URLQueryItem(name: "name", value: artist.name),
            ] + Self.optional("art", artist.artworkURL?.absoluteString))
        case let .album(album):
            return ("album", [
                URLQueryItem(name: "provider", value: album.provider.rawValue),
                URLQueryItem(name: "id", value: album.id),
                URLQueryItem(name: "name", value: album.name),
            ] + Self.optional("art", album.artworkURL?.absoluteString))
        }
    }

    // MARK: Parse

    public static func parse(_ url: URL) -> CisumLink? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let entity = entity(from: url)
        else { return nil }

        let q = Self.queryMap(comps.queryItems)

        switch entity {
        case "song":
            return parseSong(q)
        case "playlist":
            return parsePlaylist(q)
        case "artist":
            guard let provider = q["provider"].flatMap(MediaProvider.init(rawValue:)),
                  let id = nonEmpty(q["id"]),
                  let name = nonEmpty(q["name"])
            else { return nil }
            return .artist(SharedArtist(provider: provider, id: id, name: name, artworkURL: safeURL(q["art"])))
        case "album":
            guard let provider = q["provider"].flatMap(MediaProvider.init(rawValue:)),
                  let id = nonEmpty(q["id"]),
                  let name = nonEmpty(q["name"])
            else { return nil }
            return .album(SharedAlbum(provider: provider, id: id, name: name, artworkURL: safeURL(q["art"])))
        default:
            return nil
        }
    }

    /// Extracts the entity ("song"/"playlist"/…) from either `cisum://<entity>` (host) or
    /// `https://cisum.studio/<entity>` (first path segment).
    private static func entity(from url: URL) -> String? {
        if url.scheme == scheme {
            return url.host
        }
        if url.scheme == "https", let host = url.host?.lowercased(),
           host == "cisum.studio" || host == "www.cisum.studio"
        {
            return url.pathComponents.first { $0 != "/" }
        }
        return nil
    }

    private static func parseSong(_ q: [String: String]) -> CisumLink? {
        guard let provider = q["provider"].flatMap(MediaProvider.init(rawValue:)),
              let id = nonEmpty(q["id"]),
              let title = nonEmpty(q["title"]),
              let artist = q["artist"]
        else { return nil }

        return .song(SharedSong(
            provider: provider,
            id: id,
            title: title,
            artist: artist,
            album: nonEmpty(q["album"]),
            artworkURL: safeURL(q["art"]),
            durationSeconds: q["dur"].flatMap(Double.init),
            isExplicit: q["explicit"] == "1",
            isrc: nonEmpty(q["isrc"])
        ))
    }

    private static func parsePlaylist(_ q: [String: String]) -> CisumLink? {
        // Embedded tracklist takes precedence over a provider or short-id reference.
        if let blob = nonEmpty(q["data"]) {
            guard let tracks = decodeTracks(blob), let name = nonEmpty(q["name"]) else { return nil }
            return .playlist(.embedded(name: name, author: nonEmpty(q["author"]), sharedBy: nonEmpty(q["sharedby"]), tracks: tracks))
        }
        // Provider-sourced (imported) playlist: provider + source id.
        if let provider = q["provider"].flatMap(MediaProvider.init(rawValue:)),
           let id = nonEmpty(q["id"])
        {
            return .playlist(.imported(provider: provider, sourceID: id, name: nonEmpty(q["name"])))
        }
        // Shortened (web) playlist: bare short id, payload resolved server-side.
        if let id = nonEmpty(q["id"]) {
            return .playlist(.shortened(id: id, name: nonEmpty(q["name"]), author: nonEmpty(q["author"])))
        }
        return nil
    }

    // MARK: Tracklist codec (JSON → zlib → base64url), with guards

    private static func encodeTracks(_ tracks: [SharedSong]) -> String? {
        guard let json = try? JSONEncoder().encode(tracks),
              let compressed = try? (json as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return (compressed as Data).base64URLEncodedString()
    }

    private static func decodeTracks(_ blob: String) -> [SharedSong]? {
        guard blob.count <= maxDataParamChars,
              let compressed = Data(base64URLEncoded: blob),
              let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              json.count <= maxInflatedBytes,
              let tracks = try? JSONDecoder().decode([SharedSong].self, from: json),
              tracks.count <= maxEmbeddedTracks
        else { return nil }
        return tracks
    }

    // MARK: Helpers

    private static func songQueryItems(_ song: SharedSong) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "provider", value: song.provider.rawValue),
            URLQueryItem(name: "id", value: song.id),
            URLQueryItem(name: "title", value: song.title),
            URLQueryItem(name: "artist", value: song.artist),
        ]
        items += optional("album", song.album)
        items += optional("art", song.artworkURL?.absoluteString)
        items += optional("dur", song.durationSeconds.map { String($0) })
        items += optional("isrc", song.isrc)
        if song.isExplicit {
            items.append(URLQueryItem(name: "explicit", value: "1"))
        }
        return items
    }

    private static func optional(_ name: String, _ value: String?) -> [URLQueryItem] {
        guard let value, !value.isEmpty else { return [] }
        return [URLQueryItem(name: name, value: value)]
    }

    private static func queryMap(_ items: [URLQueryItem]?) -> [String: String] {
        var map: [String: String] = [:]
        for item in items ?? [] where item.value != nil {
            map[item.name] = item.value
        }
        return map
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Only accept http(s) artwork URLs from an untrusted link.
    private static func safeURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

// MARK: - base64url

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 {
            s.append("=")
        }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
