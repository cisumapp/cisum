import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    let playlistID: String

    @Environment(SearchOverlayController.self) private var searchOverlay
    @Query private var playlists: [Playlist]
    @Query private var items: [PlaylistItem]

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    init(playlistID: String) {
        self.playlistID = playlistID
        _playlists = Query(
            filter: #Predicate<Playlist> { $0.playlistID == playlistID },
            sort: \Playlist.updatedAt,
            order: .reverse
        )
        _items = Query(
            filter: #Predicate<PlaylistItem> { $0.playlistID == playlistID },
            sort: \PlaylistItem.sortIndex,
            order: .forward
        )
    }

    private var playlist: Playlist? {
        playlists.first
    }

    private var activeSearchQuery: String {
        searchOverlay.playlistQuery(for: playlistID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [PlaylistItem] {
        guard !activeSearchQuery.isEmpty else { return items }
        let normalizedQuery = activeSearchQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return items.filter { item in
            let title = item.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if title.contains(normalizedQuery) {
                return true
            }

            let artist = (item.artistName ?? "")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return artist.contains(normalizedQuery)
        }
    }

    private var playlistSearchContext: SearchOverlayContext {
        SearchOverlayContext.playlist(
            playlistID: playlistID,
            playlistTitle: playlist?.title ?? "Playlist"
        )
    }

    var body: some View {
        List {
            if let playlist {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playlist.title)
                            .font(.title3.weight(.semibold))
                        if let subtitle = playlist.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if activeSearchQuery.isEmpty {
                            Text("\(items.count) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(filteredItems.count) of \(items.count) tracks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Tracks Yet",
                        systemImage: "music.note",
                        description: Text("This playlist is ready, but no tracks have been imported yet.")
                    )
                }
            } else if filteredItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Matching Tracks",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different query or switch to global search with Cmd+Enter.")
                    )
                }
            } else {
                Section("Tracks") {
                    ForEach(filteredItems) { item in
                        PlaylistTrackRow(item: item)
                    }
                }
            }
        }
        .searchOverlayContext(playlistSearchContext)
        .navigationTitle(playlist?.title ?? "Playlist")
        .enableInjection()
    }
}

private struct PlaylistTrackRow: View {
    let item: PlaylistItem

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(item.sortIndex + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)

                if let artistName = item.artistName, !artistName.isEmpty {
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.importStatus == .uncertain {
                Text("Review")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .enableInjection()
    }
}

#Preview {
    NavigationStack {
        PlaylistDetailView(playlistID: "preview")
    }
    .environment(SearchOverlayController())
}
