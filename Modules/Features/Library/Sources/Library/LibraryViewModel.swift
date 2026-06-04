import Foundation
import Models
import SwiftData
import SwiftUI

#if canImport(SpotifySDK)
import SpotifySDK
#endif

@Observable
@MainActor
public final class LibraryViewModel {
    public enum ShelfSortMode {
        case alphabetical
        case recent
    }

    public var isPresentingImportPicker: Bool = false
    public var isPresentingYouTubeImport: Bool = false
    public var isPresentingSpotifyImport: Bool = false
    public var spotifySnapshot = SpotifyLibrarySnapshot.empty
    public var isLoadingSpotifySnapshot = false
    public var isSyncingLikedSongs = false
    public var shelfSortMode: ShelfSortMode = .alphabetical
    public var isCompactShelfMode = false
    public var isPinsExpanded = true
    public var isPlaylistsExpanded = true
    public var isRecentlyAddedExpanded = true
    public var libraryActionErrorMessage: String?

    public init() {}

    public func toggleShelfSortMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            shelfSortMode = shelfSortMode == .alphabetical ? .recent : .alphabetical
        }
    }
}
