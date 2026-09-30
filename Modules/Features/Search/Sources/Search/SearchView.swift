import Aesthetics
import Authentication
import Kingfisher
import Library
import Models
import Player
import Playlists
import SwiftData
import SwiftUI
import Tracks
import Utilities
import YouTubeSDK

#if canImport(SpotifySDK)
import SpotifySDK
#endif

public struct SearchView: View {
    @Environment(PlayerPresentationController.self) private var presentationController
    @Environment(\.searchViewModel) private var searchViewModelOptional
    @Environment(\.playbackCommands) private var playbackCommands
    @Environment(\.playlistLibraryStore) private var playlistLibraryStore
    @Environment(\.centralMediaStore) private var centralMediaStore

    private var searchViewModel: any SearchViewModelInterface {
        searchViewModelOptional!
    }

    @Environment(SpotifySessionCoordinator.self) private var spotifyCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) private var router
    #if canImport(SpotifySDK)
    #endif

    @FocusState private var isSearchFocused: Bool
    @State private var viewModel = SearchStateViewModel()
    @State private var reversedSuggestions: [String] = []

    public init() {}

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchViewModel.searchText },
            set: { searchViewModel.searchText = $0 }
        )
    }

    public var body: some View {
        content
    }

    private var content: some View {
        VStack(spacing: 0) {
            switch searchViewModel.state {
            case .idle:
                if searchViewModel.recentSearches.isEmpty {
                    ContentUnavailableView(
                        "Search for something",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    List {
                        Section("Recent Searches") {
                            ForEach(searchViewModel.recentSearches, id: \.self) { recent in
                                Button {
                                    searchViewModel.applySuggestion(recent)
                                } label: {
                                    Label(recent, systemImage: "clock")
                                        .foregroundStyle(.primary)
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let query = searchViewModel.recentSearches[index]
                                    searchViewModel.removeRecentSearch(query)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .safeAreaPadding(.top)
                    .contentMargins(.bottom, 140)
                }

            case .loading:
                ProgressView("Searching…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .error(message):
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )

            case .success:
                SearchResultsList(
                    searchViewModel: searchViewModel,
                    isImportingSpotifyPlaylistID: $viewModel.isImportingSpotifyPlaylistID,
                    showNonPlayableAlert: $viewModel.showNonPlayableAlert,
                    nonPlayableMessage: $viewModel.nonPlayableMessage,
                    onRowSelection: handleRowSelection
                )
            }

            // Custom Inverted Suggestions Overlay
            if isSearchFocused, !searchViewModel.searchText.isEmpty, !reversedSuggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(reversedSuggestions, id: \.self) { suggestion in
                            Button {
                                searchViewModel.applySuggestion(suggestion)
                                isSearchFocused = false
                            } label: {
                                HStack {
                                    Label(suggestion, systemImage: "magnifyingglass")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(x: 1, y: -1)

                            Divider()
                                .scaleEffect(x: 1, y: -1)
                        }
                    }
                }
                #if os(iOS)
                .background(Color(uiColor: .systemBackground))
                #else
                .background(Color(nsColor: .windowBackgroundColor))
                #endif
                .scaleEffect(x: 1, y: -1)
                .zIndex(100)
            }
        }
        .onSubmit(of: .search) {
            isSearchFocused = false
            viewModel.isSearchPresentationActive = false
        }
        .optionalSearchable(
            text: searchTextBinding,
            isFocused: $isSearchFocused,
            isPresented: $viewModel.isSearchPresentationActive
        )
        .alert(viewModel.actionAlertMessage, isPresented: $viewModel.showActionAlert) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: searchViewModel.suggestions) { _, newSuggestions in
            reversedSuggestions = newSuggestions.reversed()
        }
        .task {
            searchViewModel.loadRecentSearches()
        }
    }

    // MARK: - Actions

    private func handleRowSelection(_ item: FederatedSearchItem) {
        hideKeyboard()
        PerfLog.info("SearchView: handleRowSelection title='\(item.title)' service=\(item.service.rawValue) id=\(item.id)")

        switch item.payload {
        case let .youtube(ref):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playbackCommands?.load(PlayableRef(youtube: ref), preserveQueue: false)
            presentationController.expand()

        case .spotify:
            Task {
                await playSpotifyTrack(item)
            }

        case let .spotifyArtist(artist):
            navigateToArtist(artist)

        case let .spotifyPlaylist(playlist):
            Task {
                await handleSpotifyPlaylistTap(playlist)
            }

        case .providerSDK:
            // ProviderSDK tracks resolve via the same external stream path as Spotify.
            PerfLog.info("SearchView: providerSDK tap — creating playableRef")
            Task {
                await playProviderSDKTrack(item)
            }
        }
    }

    #if canImport(SpotifySDK)
    private var spotifyPlaylistImportService: SpotifyPlaylistImportService? {
        guard let sdk = spotifyCoordinator.sdk,
              let playlistLibraryStore,
              let centralMediaStore
        else { return nil }
        return SpotifyPlaylistImportService(
            sdk: sdk,
            playlistStore: playlistLibraryStore,
            onSpotifyPlaylistImported: { playlist in
                Task {
                    _ = await centralMediaStore.upsertSpotifyPlaylist(playlist)
                }
            }
        )
    }
    #endif

    private func playSpotifyTrack(_ item: FederatedSearchItem) async {
        do {
            // No pre-resolution here any more. The view supplies an identity; the player resolves
            // it, caches the stream URL, and persists the binding so the next play skips all of it.
            guard let ref = item.playableRef else {
                throw FederatedSearchError.noPlayableStream(
                    "This result has no playable source."
                )
            }

            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playbackCommands?.load(ref, preserveQueue: false)
            presentationController.expand()
        } catch {
            viewModel.nonPlayableMessage = error.localizedDescription
            viewModel.showNonPlayableAlert = true
        }
    }

    private func playProviderSDKTrack(_ item: FederatedSearchItem) async {
        do {
            // No pre-resolution here any more. The view supplies an identity; the player resolves
            // it, caches the stream URL, and persists the binding so the next play skips all of it.
            guard let ref = item.playableRef else {
                PerfLog.error("SearchView.playProviderSDKTrack: item has no playableRef — item.id=\(item.id) title='\(item.title)'")
                throw FederatedSearchError.noPlayableStream(
                    "This result has no playable source."
                )
            }

            PerfLog.info("SearchView.playProviderSDKTrack: ref.sourceID='\(ref.sourceID)' ref.sourceTrackID='\(ref.sourceTrackID)' title='\(ref.title)'")
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playbackCommands?.load(ref, preserveQueue: false)
            presentationController.expand()
        } catch {
            viewModel.nonPlayableMessage = error.localizedDescription
            viewModel.showNonPlayableAlert = true
        }
    }

    private func handleSpotifyPlaylistTap(_ playlist: SpotifySearchPlaylist) async {
        #if canImport(SpotifySDK)
        guard let playlistLibraryStore else { return }
        if let existing = await playlistLibraryStore.playlistSnapshot(
            sourceProvider: .spotify, sourcePlaylistID: playlist.id
        ) {
            router.navigate(to: .playlist(id: existing.playlistID))
            return
        }

        guard let importService = spotifyPlaylistImportService else {
            viewModel.actionAlertMessage =
                "Spotify is not connected. Open Settings and sign in first."
            viewModel.showActionAlert = true
            return
        }

        viewModel.isImportingSpotifyPlaylistID = playlist.id
        defer { viewModel.isImportingSpotifyPlaylistID = nil }

        do {
            let playlistID = try await importService.importPlaylist(id: playlist.id)
            router.navigate(to: .playlist(id: playlistID))
        } catch {
            viewModel.actionAlertMessage = error.localizedDescription
            viewModel.showActionAlert = true
        }
        #else
        viewModel.actionAlertMessage = "Spotify playlist import is unavailable on this target."
        viewModel.showActionAlert = true
        #endif
    }

    private func searchSongs(for artist: SpotifySearchArtist) {
        searchViewModel.searchScope = .music
        searchViewModel.searchText = artist.name
        isSearchFocused = true
        viewModel.isSearchPresentationActive = true
    }

    /// Upserts a SwiftData Artist stub from a Spotify search result, then navigates natively.
    private func navigateToArtist(_ spotifyArtist: SpotifySearchArtist) {
        // Check if we already have an Artist for this Spotify ID.
        let spotifyID = spotifyArtist.id
        let descriptor = FetchDescriptor<Artist>(
            predicate: #Predicate<Artist> { $0.spotifyArtistID == spotifyID }
        )
        let existing = try? modelContext.fetch(descriptor)

        if let artist = existing?.first {
            // Update artwork if we now have a better URL
            if artist.artworkURLString == nil, let url = spotifyArtist.artworkURL {
                artist.artworkURLString = url.absoluteString
                artist.updatedAt = .now
            }
            router.navigate(to: .artist(id: artist.artistID))
            return
        }

        // Create a stub artist from the search result.
        let stub = Artist(
            displayName: spotifyArtist.name,
            normalizedName: spotifyArtist.name.lowercased(),
            artworkURLString: spotifyArtist.artworkURL?.absoluteString,
            genresJSONString: spotifyArtist.genres.isEmpty
                ? nil
                : (try? String(data: JSONEncoder().encode(spotifyArtist.genres), encoding: .utf8))
                ?? nil,
            spotifyArtistID: spotifyArtist.id
        )
        modelContext.insert(stub)
        router.navigate(to: .artist(id: stub.artistID))
    }

    private func playlistID(for item: FederatedSearchItem) -> String? {
        guard case let .spotifyPlaylist(playlist) = item.payload else { return nil }
        return playlist.id
    }
}
