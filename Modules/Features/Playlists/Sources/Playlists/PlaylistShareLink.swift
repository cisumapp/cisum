import Foundation
import Models

/// Builds a shareable Universal Link for a playlist. Provider/custom playlists are shortened via the
/// backend (`POST /api/share`) so the link is tiny; if that fails, falls back to the self-contained
/// (long, embedded) https link so sharing never hard-fails.
enum PlaylistShareLink {
    private struct ShareIDResponse: Decodable { let id: String }

    static func makeShareURL(for playlist: SharedPlaylist) async -> URL? {
        guard let payload = SharedPlaylistPayload(playlist) else {
            // Already shortened, or nothing to shorten — use the direct link.
            return CisumLink.playlist(playlist).webURL()
        }
        guard let endpoint = URL(string: "https://\(CisumLink.webHost)/api/share") else {
            return CisumLink.playlist(playlist).webURL()
        }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return CisumLink.playlist(playlist).webURL()
            }
            let decoded = try JSONDecoder().decode(ShareIDResponse.self, from: data)
            let shortened = SharedPlaylist.shortened(
                id: decoded.id,
                name: readableName(playlist),
                author: readableAuthor(playlist)
            )
            return CisumLink.playlist(shortened).webURL()
        } catch {
            return CisumLink.playlist(playlist).webURL()
        }
    }

    private static func readableName(_ playlist: SharedPlaylist) -> String? {
        switch playlist {
        case let .embedded(name, _, _, _): name
        case let .imported(_, _, name): name
        case let .shortened(_, name, _): name
        }
    }

    private static func readableAuthor(_ playlist: SharedPlaylist) -> String? {
        if case let .embedded(_, author, _, _) = playlist {
            return author
        }
        return nil
    }
}
