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

    private var searchViewModel: any SearchViewModelInterface {
        searchViewModelOptional!
    }

    private var centralMediaStore: CentralMediaStore {
        CentralMediaStore(modelContainer: modelContext.container)
    }
    @Environment(SpotifySessionCoordinator.self) private var spotifyCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) private var router
    #if canImport(SpotifySDK)
    #endif

    @FocusState private var isSearchFocused: Bool
    @State private var viewModel = SearchStateViewModel()

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
            ZStack {
                switch searchViewModel.state {
                case .idle:
                    if searchViewModel.recentSearches.isEmpty {
                        ContentUnavailableView(
                            "Search for something", systemImage: "magnifyingglass")
                    } else {
                        List {
                            Section {
                                ForEach(searchViewModel.recentSearches, id: \.self) { recent in
                                    Button {
                                        searchViewModel.applySuggestion(recent)
                                    } label: {
                                        Label(recent, systemImage: "clock")
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let query = searchViewModel.recentSearches[index]
                                        searchViewModel.removeRecentSearch(query)
                                    }
                                }
                            } header: {
                                SearchSectionHeader(title: "Recent Searches", subtitle: "")
                            }
                        }
                        .listStyle(.plain)
                        .contentMargins(.bottom, 140)
                    }

                case .loading:
                    ProgressView("Searching…")
                        .controlSize(.large)

                case .error(let message):
                    ContentUnavailableView(
                        "Error", systemImage: "exclamationmark.triangle", description: Text(message)
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
                if isSearchFocused && !searchViewModel.searchText.isEmpty && !searchViewModel.suggestions.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(searchViewModel.suggestions.reversed(), id: \.self) { suggestion in
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
        .onAppear {
            searchViewModel.loadRecentSearches()
        }
    }

    // MARK: - Actions

    private func handleRowSelection(_ item: FederatedSearchItem) {
        hideKeyboard()

        switch item.payload {
        case .youtubeMusic(let song):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(song: song, preserveQueue: false)
            presentationController.expand()

        case .youtubeVideo(let video):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.load(video: video, preserveQueue: false)
            presentationController.expand()

        case .spotify:
            Task {
                await playSpotifyTrack(item)
            }

        case .spotifyArtist(let artist):
            navigateToArtist(artist)

        case .spotifyPlaylist(let playlist):
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

    private var playlistLibraryStore: PlaylistLibraryStore {
        PlaylistLibraryStore(modelContainer: modelContext.container)
    }

    #if canImport(SpotifySDK)
        private var spotifyPlaylistImportService: SpotifyPlaylistImportService? {
            guard let sdk = spotifyCoordinator.sdk else { return nil }
            return SpotifyPlaylistImportService(
                sdk: sdk,
                playlistStore: playlistLibraryStore,
                onSpotifyPlaylistImported: { [container = modelContext.container] playlist in
                    let centralMediaStore = CentralMediaStore(modelContainer: container)
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
        guard case .spotifyPlaylist(let playlist) = item.payload else { return nil }
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

// MARK: - Search Results List

private struct SearchResultsList: View {
    let searchViewModel: any SearchViewModelInterface
    let playerViewModel: any PlayerViewModelInterface
    @Binding var isImportingSpotifyPlaylistID: String?
    @Binding var showNonPlayableAlert: Bool
    @Binding var nonPlayableMessage: String
    let onRowSelection: (FederatedSearchItem) -> Void

    var body: some View {
        let hasSpotifyTracks = !searchViewModel.spotifyTrackResults.isEmpty
        let hasSpotifyArtists = !searchViewModel.spotifyArtistResults.isEmpty
        let hasSpotifyPlaylists = !searchViewModel.spotifyPlaylistResults.isEmpty
        let hasSpotify = hasSpotifyTracks || hasSpotifyArtists || hasSpotifyPlaylists
        let hasHiddenTopResults = !searchViewModel.unifiedTopResults.isEmpty

        List {
            // MARK: Spotify Tracks

            if hasSpotifyTracks {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(searchViewModel.spotifyTrackResults) { item in
                                Button {
                                    onRowSelection(item)
                                } label: {
                                    TrackCard(
                                        trackName: item.title,
                                        artistName: item.subtitle,
                                        duration: item.displayDuration ?? "",
                                        artworkURL: item.artworkURL,
                                        artworkColor: .blue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    SearchSectionHeader(title: "Tracks", subtitle: "From Spotify")
                }
            }

            // MARK: Spotify Artists

            if hasSpotifyArtists {
                Section {
                    ForEach(searchViewModel.spotifyArtistResults) { item in
                        Button {
                            onRowSelection(item)
                        } label: {
                            SearchArtistRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    SearchSectionHeader(title: "Artists", subtitle: "From Spotify")
                }
            }

            // MARK: Spotify Playlists

            if hasSpotifyPlaylists {
                Section {
                    ForEach(searchViewModel.spotifyPlaylistResults) { item in
                        let playlistID = playlistID(for: item)
                        Button {
                            onRowSelection(item)
                        } label: {
                            SearchPlaylistRow(
                                item: item,
                                isImporting: isImportingSpotifyPlaylistID == playlistID
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingSpotifyPlaylistID == playlistID)
                    }
                } header: {
                    SearchSectionHeader(title: "Playlists", subtitle: "From Spotify")
                }
            }

            // MARK: Additional Results

            if hasHiddenTopResults {
                Section {
                    if searchViewModel.unifiedTopResults.isEmpty {
                        Text("No results")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(searchViewModel.unifiedTopResults) { item in
                                    Button {
                                        onRowSelection(item)
                                    } label: {
                                        TrackCard(
                                            trackName: item.title,
                                            artistName: item.subtitle,
                                            duration: item.displayDuration ?? "",
                                            artworkURL: item.artworkURL,
                                            artworkColor: .blue
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    SearchSectionHeader(title: "Top Results", subtitle: "Unified Search")
                }
            }

            // MARK: You Might Like

            if !searchViewModel.youMightLikeResults.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(searchViewModel.youMightLikeResults) { item in
                                Button {
                                    onRowSelection(item)
                                } label: {
                                    TrackCard(
                                        trackName: item.title,
                                        artistName: item.subtitle,
                                        duration: item.displayDuration ?? "",
                                        artworkURL: item.artworkURL,
                                        artworkColor: .blue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You Might Like")
                        if let anchorTitle =
                            (searchViewModel.spotifyTrackResults.first
                            ?? searchViewModel.unifiedTopResults.first)?.title {
                            Text("Similar to \"\(anchorTitle)\"")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: Empty Spotify state

            if hasSpotify == false, hasHiddenTopResults == false {
                Section {
                    Label(
                        "Connect Spotify in Settings for richer results.",
                        systemImage: "person.crop.circle.badge.plus"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .contentMargins(.bottom, 140)
        .listStyle(.plain)
        .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func playlistID(for item: FederatedSearchItem) -> String? {
        guard case .spotifyPlaylist(let playlist) = item.payload else { return nil }
        return playlist.id
    }
}
