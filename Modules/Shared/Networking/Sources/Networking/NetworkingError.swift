import Foundation

/// Represents common networking errors that can occur during API requests.
public enum NetworkingError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case noData
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "The URL provided is invalid: \(url)"
        case .invalidResponse:
            "The server returned an invalid response."
        case let .httpError(statusCode, _):
            "The server returned an HTTP error code: \(statusCode)"
        case let .decodingFailed(error):
            "Failed to decode the response: \(error.localizedDescription)"
        case let .encodingFailed(error):
            "Failed to encode the request body: \(error.localizedDescription)"
        case .noData:
            "No data was returned from the server."
        case .unauthorized:
            "The request is unauthorized. Please check your authentication tokens."
        }
    }
}
