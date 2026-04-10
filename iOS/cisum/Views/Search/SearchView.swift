//
//  SearchView.swift
//  cisum
//
//  Created by Aarav Gupta on 04/12/25.
//

import YouTubeSDK
import SwiftUI

struct SearchView: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.playerPresentationActions) private var playerPresentationActions

    @FocusState private var isSearchFocused: Bool
    @State private var isSearchPresentationActive: Bool = false
    @State private var showNonPlayableAlert: Bool = false
    @State private var nonPlayableMessage: String = ""

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        searchContent
            .safeAreaPadding(.top, 20)
            .optionalSearchable(
                text: Bindable(searchViewModel).searchText,
                isFocused: $isSearchFocused,
                isPresented: $isSearchPresentationActive,
                suggestions: searchViewModel.suggestions,
                onSuggestionTap: { suggestion in
                    searchViewModel.applySuggestion(suggestion)
                }
            )
            .enableInjection()
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            if shouldShowInlineSuggestions && !searchViewModel.suggestions.isEmpty {
                SuggestionsList()
            }
            
            ZStack {
                switch searchViewModel.state {
                case .idle:
                    ContentUnavailableView("Search for something", systemImage: "magnifyingglass")
                    
                case .loading:
                    ProgressView("Searching across services...")
                        .controlSize(.large)
                    
                case .error(let message):
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
                    
                case .success:
                    ResultsList()
                }
            }
        }
        .enableInjection()
        .onSubmit(of: .search) {
            isSearchFocused = false
            isSearchPresentationActive = false
        }
    }

    private var shouldShowInlineSuggestions: Bool {
        if #available(iOS 26.0, *) {
            return false
        } else {
            return false
        }
    }
    
    // MARK: - Subviews
    @ViewBuilder
    private func ResultsList() -> some View {
        List {
            ForEach(FederatedService.allCases) { service in
                Section(service.rawValue) {
                    sectionContent(for: service)
                }
            }
        }
        .contentMargins(.bottom, 140)
        .listStyle(.plain)
        .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func SuggestionsList() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchViewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        searchViewModel.applySuggestion(suggestion)
                        isSearchFocused = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.caption)
                            Text(suggestion)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 4)
    }
    
    // MARK: - Actions
    private func handleRowSelection(_ item: FederatedSearchItem) {
        switch item.payload {
        case .youtubeMusic(let song):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            let queue = searchViewModel.items(for: .youtubeMusic).compactMap { entry -> YouTubeMusicSong? in
                guard case .youtubeMusic(let queueSong) = entry.payload else { return nil }
                return queueSong
            }
            playerViewModel.load(song: song, in: queue, source: .searchMusic)
            playerPresentationActions.expand()

        case .youtubeVideo(let video):
            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            let queue = searchViewModel.items(for: .youtube).compactMap { entry -> YouTubeVideo? in
                guard case .youtubeVideo(let queueVideo) = entry.payload else { return nil }
                return queueVideo
            }
            playerViewModel.load(video: video, in: queue, source: .searchVideo)
            playerPresentationActions.expand()

        case .tidal, .spotify:
            Task {
                await playExternalStream(from: item)
            }
        }
    }

    @MainActor
    private func playExternalStream(from item: FederatedSearchItem) async {
        do {
            guard let payload = try await searchViewModel.resolveExternalStream(for: item) else {
                return
            }

            searchViewModel.recordSuccessfulPlayFromCurrentQuery()
            playerViewModel.loadExternalStream(
                mediaID: payload.mediaID,
                streamURL: payload.streamURL,
                title: payload.title,
                artist: payload.artist,
                artworkURL: payload.artworkURL,
                service: payload.service,
                qualityLabel: payload.qualityLabel,
                codecLabel: payload.codecLabel
            )
            playerPresentationActions.expand()
        } catch {
            nonPlayableMessage = error.localizedDescription
            showNonPlayableAlert = true
        }
    }

    @ViewBuilder
    private func sectionContent(for service: FederatedService) -> some View {
        let state = searchViewModel.sectionState(for: service)
        let items = searchViewModel.items(for: service)

        switch state {
        case .idle:
            Text("Start typing to search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading \(service.rawValue) results...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .success:
            if items.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        handleRowSelection(item)
                    } label: {
                        federatedRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func federatedRow(_ item: FederatedSearchItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let duration = item.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if !item.isPlayable {
                    Text("Metadata")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .contentShape(.rect)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }
}

#Preview {
    SearchView()
        .environment(PlayerViewModel())
        .environment(SearchViewModel())
}

extension View {
    @ViewBuilder
    func optionalSearchable(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        isPresented: Binding<Bool>,
        suggestions: [String],
        onSuggestionTap: @escaping (String) -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .searchable(
                    text: text,
                    isPresented: isPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search")
                )
                .searchFocused(isFocused)
//                .searchSuggestions {
//                    ForEach(suggestions, id: \.self) { suggestion in
//                        Button(suggestion) {
//                            onSuggestionTap(suggestion)
//                        }
//                    }
//                }
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .searchToolbarBehavior(.minimize)
        } else {
            self
//                .searchable(text: text, prompt: Text("Search"))
//                .searchSuggestions {
//                    ForEach(suggestions, id: \.self) { suggestion in
//                        Button(suggestion) {
//                            onSuggestionTap(suggestion)
//                        }
//                    }
//                }
        }
    }
}
