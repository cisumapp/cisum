import SwiftUI

@Observable
@MainActor
public final class SearchStateViewModel {
    public var isSearchPresentationActive: Bool = false
    public var showNonPlayableAlert: Bool = false
    public var nonPlayableMessage: String = ""
    public var isImportingSpotifyPlaylistID: String?
    public var actionAlertMessage: String = ""
    public var showActionAlert: Bool = false

    public init() {}
}
