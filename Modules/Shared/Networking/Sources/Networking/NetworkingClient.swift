import Foundation

/// A modern, async/await HTTP networking client designed with Swift 6 Concurrency in mind.
/// It utilizes `URLSession` to perform generic, strongly-typed network requests.
public actor NetworkingClient {
    /// The shared, singleton instance of the client.
    public static let shared = NetworkingClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Initializes a new `NetworkingClient`.
    /// - Parameters:
    ///   - session: The `URLSession` to use for requests. Defaults to `.shared`.
    ///   - decoder: The `JSONDecoder` used for decoding responses.
    ///   - encoder: The `JSONEncoder` used for encoding request bodies.
    public init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    // MARK: - Generic Request Execution

    /// Executes a URLRequest and decodes the response into the specified Decodable type.
    /// - Parameters:
    ///   - request: The configured `URLRequest`.
    ///   - type: The `Decodable` type to decode the response into.
    /// - Returns: The decoded object.
    /// - Throws: `NetworkingError` if the request, response, or decoding fails.
    public func execute<T: Decodable & Sendable>(
        request: URLRequest,
        responseType _: T.Type
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkingError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkingError.decodingFailed(error)
            }
        case 401, 403:
            throw NetworkingError.unauthorized
        default:
            throw NetworkingError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Convenience Methods

    /// Downloads raw data from a GET request (useful for images, files).
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - headers: Optional HTTP headers.
    /// - Returns: The raw `Data` returned by the server.
    public func downloadData(
        url: URL,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkingError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return data
        case 401, 403:
            throw NetworkingError.unauthorized
        default:
            throw NetworkingError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Performs a standard GET request.
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - headers: Optional HTTP headers to include in the request.
    ///   - responseType: The expected `Decodable` type.
    /// - Returns: The decoded object.
    public func get<T: Decodable & Sendable>(
        url: URL,
        headers: [String: String]? = nil,
        responseType type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await execute(request: request, responseType: type)
    }

    /// Performs a generic POST request where the body conforms to `Encodable & Sendable`.
    /// This ensures strict Swift 6 safety across actor boundaries.
    /// - Parameters:
    ///   - url: The target URL.
    ///   - body: The model to encode as JSON. Must be `Encodable` and `Sendable`.
    ///   - headers: Optional HTTP headers. `Content-Type: application/json` is added by default.
    ///   - responseType: The expected `Decodable` type.
    /// - Returns: The decoded object.
    public func sendablePost<T: Decodable & Sendable>(
        url: URL,
        body: some Encodable & Sendable,
        headers: [String: String]? = nil,
        responseType type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw NetworkingError.encodingFailed(error)
        }

        return try await execute(request: request, responseType: type)
    }

    /// Performs a standard POST request with raw data.
    /// - Parameters:
    ///   - url: The target URL.
    ///   - bodyData: The raw `Data` to send.
    ///   - headers: Optional HTTP headers.
    ///   - responseType: The expected `Decodable` type.
    /// - Returns: The decoded object.
    public func post<T: Decodable & Sendable>(
        url: URL,
        bodyData: Data,
        headers: [String: String]? = nil,
        responseType type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = bodyData

        return try await execute(request: request, responseType: type)
    }
}
