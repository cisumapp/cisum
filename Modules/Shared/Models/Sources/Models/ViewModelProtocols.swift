import Foundation
import Observation
import SwiftUI

public enum ArtworkVideoProcessingStatus: Equatable, Sendable {
    case idle
    case processing
    case ready
    case failed
}

/// Single cycling playback mode surfaced in the now-playing menu (Apple Music style).
/// Shuffle and repeat are mutually exclusive here; cycling order is off → shuffle → repeatAll → repeatOne.
public enum PlaybackMode: String, Sendable, CaseIterable {
    case off
    case shuffle
    case repeatAll
    case repeatOne
}

@MainActor
public protocol SearchViewModelInterface: AnyObject, Observable {
    var searchText: String { get set }
    var suggestions: [String] { get }
    var state: SearchState { get }
    var searchScope: SearchScope { get set }
    var recentSearches: [String] { get }
    func loadRecentSearches()
    func removeRecentSearch(_ query: String)

    // Results
    var spotifyTrackResults: [FederatedSearchItem] { get }
    var spotifyArtistResults: [FederatedSearchItem] { get }
    var spotifyPlaylistResults: [FederatedSearchItem] { get }
    var unifiedTopResults: [FederatedSearchItem] { get }
    var youMightLikeResults: [FederatedSearchItem] { get }
    var hiddenFallbackMap: [String: FederatedSearchItem] { get }

    func applySuggestion(_ suggestion: String)
    func recordSuccessfulPlayFromCurrentQuery()
    func resolveExternalStream(for item: FederatedSearchItem) async throws -> ExternalStreamPayload?

    // Pagination helpers
    var isVideoPaginationLoading: Bool { get }
    func performDebouncedSearch()
}

// MARK: - Search Support Types

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case music = "Music"
    case video = "Videos"

    public var id: String {
        rawValue
    }
}

public enum SearchState: Equatable, Sendable {
    case idle
    case loading
    case error(String)
    case success
}
