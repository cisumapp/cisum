import Authentication
import Foundation
import Networking
import SwiftUI

// MARK: - Data Types

public struct LastFMPlaybackItem: Sendable, Equatable {
    public let mediaID: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let trackNumber: UInt?
    public let durationSeconds: UInt?
    public let contextURL: URL?
    public let mbid: String?
    public let albumArtist: String?

    public init(
        mediaID: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        trackNumber: UInt? = nil,
        durationSeconds: UInt? = nil,
        contextURL: URL? = nil,
        mbid: String? = nil,
        albumArtist: String? = nil
    ) {
        self.mediaID = mediaID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.trackNumber = trackNumber
        self.durationSeconds = durationSeconds
        self.contextURL = contextURL
        self.mbid = mbid
        self.albumArtist = albumArtist
    }
}

public struct LastFMConfiguration: Sendable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

// MARK: - Server Response Types

public struct LastFMConnectionStatus: Sendable, Codable {
    public let connected: Bool
    public let lastfmUsername: String?
    public let connectedAt: String?
    public let pendingFlowId: String?
    public let pendingFlowExpiresAt: String?
}

public struct LastFMConnectionFlow: Sendable, Codable {
    public let flowId: String
    public let authorizeUrl: String
    public let expiresAt: String
}

public struct LastFMConnectionResult: Sendable, Codable {
    public let connected: Bool
    public let lastfmUsername: String?
    public let connectedAt: String?
}

public actor LastFMScrobbler {
    private static let baseURL = "https://cisum.studio"

    private var configuration = LastFMConfiguration()
    private var recentPlays: [LastFMPlaybackItem] = []
    private let authService: AuthService

    public init(configuration: LastFMConfiguration = .init(), authService: AuthService) {
        self.configuration = configuration
        self.authService = authService
    }

    public func configure(_ configuration: LastFMConfiguration) {
        self.configuration = configuration
    }

    public var isEnabled: Bool {
        configuration.enabled
    }

    // MARK: - API Payloads

    private struct LastFMActionRequest<T: Encodable & Sendable>: Encodable {
        let action: String
        let payload: T?
        let flowId: String?

        init(action: String, payload: T? = nil, flowId: String? = nil) {
            self.action = action
            self.payload = payload
            self.flowId = flowId
        }
    }

    private struct EmptyPayload: Codable {}

    private struct PlaybackPayload: Encodable {
        let mediaId: String
        let title: String
        let artist: String
        let album: String?
        let artworkUrl: String?
        let trackNumber: UInt?
        let durationSeconds: UInt?
        let contextUrl: String?
        let mbid: String?
        let albumArtist: String?
        var playedAt: String?
    }

    // MARK: - Playback Scrobbling

    public func recordNowPlaying(_ item: LastFMPlaybackItem) async throws {
        guard isEnabled else { return }
        guard let token = await authService.getSessionToken() else { return }

        let payload = buildPayload(from: item)
        let request = LastFMActionRequest(action: "nowPlaying", payload: payload)

        try await postToLastFMAPI(body: request, token: token, responseType: EmptyPayload.self)
        recentPlays.append(item)
    }

    public func scrobble(_ item: LastFMPlaybackItem, playedAt date: Date = .now) async throws {
        guard isEnabled else { return }
        guard let token = await authService.getSessionToken() else { return }

        var payload = buildPayload(from: item)
        payload.playedAt = ISO8601DateFormatter().string(from: date)

        let request = LastFMActionRequest(action: "scrobble", payload: payload)

        try await postToLastFMAPI(body: request, token: token, responseType: EmptyPayload.self)
        recentPlays.append(item)
    }

    public func recentPlayHistory() -> [LastFMPlaybackItem] {
        recentPlays
    }

    // MARK: - Connection Management

    public func checkConnectionStatus() async throws -> LastFMConnectionStatus {
        guard let token = await authService.getSessionToken() else {
            return LastFMConnectionStatus(
                connected: false,
                lastfmUsername: nil,
                connectedAt: nil,
                pendingFlowId: nil,
                pendingFlowExpiresAt: nil
            )
        }

        let url = URL(string: "\(Self.baseURL)/api/lastfm")!
        let headers = ["Authorization": "Bearer \(token)"]

        return try await executeWithLastFMErrorHandling {
            try await NetworkingClient.shared.get(
                url: url,
                headers: headers,
                responseType: LastFMConnectionStatus.self
            )
        }
    }

    public func startConnection() async throws -> LastFMConnectionFlow {
        guard let token = await authService.getSessionToken() else {
            throw LastFMAPIError.notAuthenticated
        }

        let request = LastFMActionRequest<EmptyPayload>(action: "start")
        return try await postToLastFMAPI(body: request, token: token, responseType: LastFMConnectionFlow.self)
    }

    public func completeConnection(flowId: String) async throws -> LastFMConnectionResult {
        guard let token = await authService.getSessionToken() else {
            throw LastFMAPIError.notAuthenticated
        }

        let request = LastFMActionRequest<EmptyPayload>(action: "complete", flowId: flowId)
        return try await postToLastFMAPI(body: request, token: token, responseType: LastFMConnectionResult.self)
    }

    public func disconnect() async throws {
        guard let token = await authService.getSessionToken() else {
            throw LastFMAPIError.notAuthenticated
        }

        let request = LastFMActionRequest<EmptyPayload>(action: "disconnect")
        try await postToLastFMAPI(body: request, token: token, responseType: EmptyPayload.self)
    }

    // MARK: - HTTP Helpers

    private func buildPayload(from item: LastFMPlaybackItem) -> PlaybackPayload {
        PlaybackPayload(
            mediaId: item.mediaID,
            title: item.title,
            artist: item.artist,
            album: item.album,
            artworkUrl: item.artworkURL?.absoluteString,
            trackNumber: item.trackNumber,
            durationSeconds: item.durationSeconds,
            contextUrl: item.contextURL?.absoluteString,
            mbid: item.mbid,
            albumArtist: item.albumArtist,
            playedAt: nil
        )
    }

    @discardableResult
    private func postToLastFMAPI<R: Decodable & Sendable>(
        body: some Encodable & Sendable,
        token: String,
        responseType: R.Type
    ) async throws -> R {
        let url = URL(string: "\(Self.baseURL)/api/lastfm")!
        let headers = ["Authorization": "Bearer \(token)"]

        return try await executeWithLastFMErrorHandling {
            try await NetworkingClient.shared.sendablePost(
                url: url,
                body: body,
                headers: headers,
                responseType: responseType
            )
        }
    }

    private func executeWithLastFMErrorHandling<T>(
        requestBuilder: () async throws -> T
    ) async throws -> T {
        do {
            return try await requestBuilder()
        } catch let NetworkingError.httpError(statusCode, data) {
            let errorMessage: String = if let data,
                                          let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                          let message = errorJSON["error"] as? String
            {
                message
            } else {
                "Last.fm API request failed with status \(statusCode)"
            }
            throw LastFMAPIError.serverError(statusCode: statusCode, message: errorMessage)
        } catch {
            throw error
        }
    }
}

// MARK: - Errors

public enum LastFMAPIError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Sign in to your cisum account to use Last.fm"
        case .invalidResponse:
            "Received an invalid response from the server"
        case let .serverError(_, message):
            message
        }
    }
}

public extension EnvironmentValues {
    @Entry var lastFMScrobbler: LastFMScrobbler?
}
