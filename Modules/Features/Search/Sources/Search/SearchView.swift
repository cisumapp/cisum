import Aesthetics
import Kingfisher
import Library
import Models
import Player
import Playlists
import Plugins
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
    @Environment(\.playerViewModel) private var playerViewModel
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
                    playerViewModel: playerViewModel,
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

        switch item.payload {
        case let .youtubeMusic(song):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(song: song, preserveQueue: false)
            presentationController.expand()

        case let .youtubeVideo(video):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(video: video, preserveQueue: false)
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

        case .providerSDKTrack:
            // ProviderSDK tracks resolve via the same external stream path as Spotify.
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
            guard let selectedPayload = try await searchViewModel.resolveExternalStream(for: item)
            else {
                throw FederatedSearchError.noPlayableStream(
                    "Unable to resolve a YouTube-backed stream for this Spotify track."
                )
            }

            guard
                let selectedTrack = makeExternalQueueTrack(
                    for: item,
                    preResolvedPayload: selectedPayload
                )
            else {
                throw FederatedSearchError.noPlayableStream(
                    "Unable to build the Spotify playback track."
                )
            }

            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(external: selectedTrack, preserveQueue: false)
            presentationController.expand()
        } catch {
            viewModel.nonPlayableMessage = error.localizedDescription
            viewModel.showNonPlayableAlert = true
        }
    }

    private func playProviderSDKTrack(_ item: FederatedSearchItem) async {
        do {
            guard let selectedPayload = try await searchViewModel.resolveExternalStream(for: item)
            else {
                throw FederatedSearchError.noPlayableStream(
                    "Unable to resolve a stream for this track."
                )
            }

            guard
                let selectedTrack = makeExternalQueueTrack(
                    for: item,
                    preResolvedPayload: selectedPayload
                )
            else {
                throw FederatedSearchError.noPlayableStream(
                    "Unable to build the playback track."
                )
            }

            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(external: selectedTrack, preserveQueue: false)
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

    private func makeExternalQueueTracks(
        from items: [FederatedSearchItem],
        selectedItemID: String,
        selectedPayload: ExternalStreamPayload
    ) -> [ExternalQueueTrack] {
        let tracks = items.compactMap { entry in
            makeExternalQueueTrack(
                for: entry,
                preResolvedPayload: entry.id == selectedItemID ? selectedPayload : nil
            )
        }

        if tracks.isEmpty {
            let fallbackTrack = ExternalQueueTrack(
                mediaID: selectedPayload.mediaID,
                title: selectedPayload.title,
                artist: selectedPayload.artist,
                artworkURL: selectedPayload.artworkURL,
                service: selectedPayload.service,
                isExplicit: false,
                qualityLabelHint: selectedPayload.qualityLabel,
                codecLabelHint: selectedPayload.codecLabel,
                resolvePayload: {
                    selectedPayload
                }
            )
            return [fallbackTrack]
        }

        return tracks
    }

    private func makeExternalQueueTrack(
        for item: FederatedSearchItem,
        preResolvedPayload: ExternalStreamPayload? = nil
    ) -> ExternalQueueTrack? {
        switch item.payload {
        case .spotify, .youtubeMusic, .youtubeVideo, .providerSDKTrack:
            break
        case .spotifyArtist, .spotifyPlaylist:
            return nil
        }

        let mediaID = preResolvedPayload?.mediaID ?? item.id

        return ExternalQueueTrack(
            mediaID: mediaID,
            title: preResolvedPayload?.title ?? item.title,
            artist: preResolvedPayload?.artist ?? item.displayArtist,
            artworkURL: preResolvedPayload?.artworkURL ?? item.artworkURL,
            service: preResolvedPayload?.service ?? item.service,
            isExplicit: item.isExplicit,
            qualityLabelHint: preResolvedPayload?.qualityLabel ?? item.audioQualityLabel,
            codecLabelHint: preResolvedPayload?.codecLabel ?? item.audioCodecLabel,
            resolvePayload: {
                if let preResolvedPayload {
                    return preResolvedPayload
                }

                guard let payload = try await searchViewModel.resolveExternalStream(for: item)
                else {
                    throw FederatedSearchError.noPlayableStream(
                        "Unable to resolve a playable stream for this track."
                    )
                }
                return payload
            }
        )
    }
}


