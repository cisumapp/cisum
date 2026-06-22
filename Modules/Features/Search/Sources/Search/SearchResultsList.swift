import Aesthetics
import Kingfisher
import Library
import Models
import Player
import SwiftUI
import Tracks

// MARK: - Search Results List

struct SearchResultsList: View {
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
            if hasHiddenTopResults {
                TopResultsSection(results: searchViewModel.unifiedTopResults, onSelect: onRowSelection)
            }

            if hasSpotifyTracks {
                SpotifyTrackSection(results: searchViewModel.spotifyTrackResults, onSelect: onRowSelection)
            }

            if hasSpotifyArtists {
                SpotifyArtistSection(results: searchViewModel.spotifyArtistResults, onSelect: onRowSelection)
            }

            if hasSpotifyPlaylists {
                SpotifyPlaylistSection(
                    results: searchViewModel.spotifyPlaylistResults,
                    isImportingID: isImportingSpotifyPlaylistID,
                    onSelect: onRowSelection
                )
            }

            if !searchViewModel.youMightLikeResults.isEmpty {
                YouMightLikeSection(
                    results: searchViewModel.youMightLikeResults,
                    anchorTitle: (
                        searchViewModel.spotifyTrackResults.first
                            ?? searchViewModel.unifiedTopResults.first
                    )?.title,
                    onSelect: onRowSelection
                )
            }

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
        .safeAreaPadding(.top, 40)
        .contentMargins(.bottom, 140)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .alert(nonPlayableMessage, isPresented: $showNonPlayableAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func playlistID(for item: FederatedSearchItem) -> String? {
        guard case let .spotifyPlaylist(playlist) = item.payload else { return nil }
        return playlist.id
    }
}

// MARK: - Section Subviews

private struct SpotifyTrackSection: View {
    let results: [FederatedSearchItem]
    let onSelect: (FederatedSearchItem) -> Void

    var body: some View {
        Section {
            ForEach(results) { item in
                Button { onSelect(item) } label: {
                    TrackListItem(
                        trackName: item.title,
                        artistName: item.subtitle,
                        duration: item.displayDuration ?? "",
                        artworkURL: item.artworkURL,
                        isExplicit: item.isExplicit
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .listRowSeparator(.hidden)
            }
        } header: {
            SearchSectionHeader(title: "Tracks", subtitle: "From Spotify")
        }
    }
}

private struct SpotifyArtistSection: View {
    let results: [FederatedSearchItem]
    let onSelect: (FederatedSearchItem) -> Void

    var body: some View {
        Section {
            ForEach(results) { item in
                Button { onSelect(item) } label: {
                    SearchArtistRow(item: item)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        } header: {
            SearchSectionHeader(title: "Artists", subtitle: "From Spotify")
        }
    }
}

private struct SpotifyPlaylistSection: View {
    let results: [FederatedSearchItem]
    let isImportingID: String?
    let onSelect: (FederatedSearchItem) -> Void

    var body: some View {
        Section {
            ForEach(results) { item in
                let playlistID = extractPlaylistID(for: item)
                Button { onSelect(item) } label: {
                    SearchPlaylistRow(
                        item: item,
                        isImporting: isImportingID == playlistID
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .disabled(isImportingID == playlistID)
            }
        } header: {
            SearchSectionHeader(title: "Playlists", subtitle: "From Spotify")
        }
    }

    private func extractPlaylistID(for item: FederatedSearchItem) -> String? {
        guard case let .spotifyPlaylist(playlist) = item.payload else { return nil }
        return playlist.id
    }
}

private struct TopResultsSection: View {
    let results: [FederatedSearchItem]
    let onSelect: (FederatedSearchItem) -> Void

    var body: some View {
        Section {
            ForEach(results) { item in
                Button { onSelect(item) } label: {
                    TrackListItem(
                        trackName: item.title,
                        artistName: item.subtitle,
                        duration: item.displayDuration ?? "",
                        artworkURL: item.artworkURL,
                        isExplicit: item.isExplicit
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .listRowSeparator(.hidden)
            }
        } header: {
            SearchSectionHeader(title: "Top Results", subtitle: "Unified Search")
        }
    }
}

private struct YouMightLikeSection: View {
    let results: [FederatedSearchItem]
    let anchorTitle: String?
    let onSelect: (FederatedSearchItem) -> Void

    var body: some View {
        Section {
            ForEach(results) { item in
                Button { onSelect(item) } label: {
                    TrackListItem(
                        trackName: item.title,
                        artistName: item.subtitle,
                        duration: item.displayDuration ?? "",
                        artworkURL: item.artworkURL,
                        isExplicit: item.isExplicit
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .listRowSeparator(.hidden)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("You Might Like")
                if let anchorTitle {
                    Text("Similar to \"\(anchorTitle)\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
