import Foundation

/// Defines a protocol for providing authentication tokens asynchronously.
/// This allows the `NetworkingClient` to dynamically fetch tokens without tightly coupling to an `AuthService`.
public protocol AuthenticationProvider: Sendable {
    func getValidAccessToken() async throws -> String
}

public extension NetworkingClient {
    /// Performs an authenticated GET request by injecting the bearer token.
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - authProvider: An object capable of providing a valid access token.
    ///   - headers: Optional additional headers.
    ///   - responseType: The expected `Decodable` type.
    /// - Returns: The decoded object.
    func authenticatedGet<T: Decodable & Sendable>(
        url: URL,
        authProvider: any AuthenticationProvider,
        headers: [String: String]? = nil,
        responseType type: T.Type
    ) async throws -> T {
        var mutableHeaders = headers ?? [:]

        let token = try await authProvider.getValidAccessToken()
        mutableHeaders["Authorization"] = "Bearer \(token)"

        return try await get(url: url, headers: mutableHeaders, responseType: type)
    }

    /// Performs an authenticated POST request with a Sendable body.
    /// - Parameters:
    ///   - url: The target URL.
    ///   - body: The `Encodable & Sendable` payload.
    ///   - authProvider: An object capable of providing a valid access token.
    ///   - headers: Optional additional headers.
    ///   - responseType: The expected `Decodable` type.
    /// - Returns: The decoded object.
    func authenticatedSendablePost<T: Decodable & Sendable>(
        url: URL,
        body: some Encodable & Sendable,
        authProvider: any AuthenticationProvider,
        headers: [String: String]? = nil,
        responseType type: T.Type
    ) async throws -> T {
        var mutableHeaders = headers ?? [:]

        let token = try await authProvider.getValidAccessToken()
        mutableHeaders["Authorization"] = "Bearer \(token)"

        return try await sendablePost(url: url, body: body, headers: mutableHeaders, responseType: type)
    }
}
