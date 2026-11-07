//
//  ArtistCatalogSections.swift
//  Artists
//
//  The artist page's sections filled from the Catalog (YouTube Music and Apple's catalogue),
//  so an artist with nothing in the library still has a full page.
//

import Aesthetics
import Albums
import Catalog
import Models
import Playlists
import SwiftData
import SwiftUI
import Tracks
import Utilities

/// A section heading in the page's style: "Title ›".
struct ArtistSectionHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.title)
            Image(systemName: "chevron.right")
                .font(.system(size: 18))
        }
        .bold()
        .legibleForeground(.primary)
    }
}

/// A heading over a row of cards that scrolls edge to edge: each card carries its own padding.
struct ArtistShelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading) {
            ArtistSectionHeader(title: title)
                .padding(.horizontal)
                .padding(.bottom)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    content
                }
            }
            .scrollClipDisabled()
        }
        .padding(.vertical)
    }
}

/// The songs the user has saved by this artist, one row into the Library's page for them.
/// Hidden when there are none.
struct ArtistSavedSongsRow: View {
    let artistName: String

    @Query private var items: [PlaylistItem]
    @Environment(\.router) private var router

    init(artistName: String) {
        self.artistName = artistName
        _items = Query(filter: #Predicate<PlaylistItem> { item in
            item.artistName?.localizedStandardContains(artistName) ?? false
        })
    }

    var body: some View {
        let id = LibraryIndex.artistID(forName: artistName)
        if let saved = LibraryIndex(items: items).artists.first(where: { $0.id == id }) {
            Button {
                router.navigate(to: .libraryArtist(id: saved.id))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .legibleForeground(.accent)
                    Text("Saved Songs")
                        .font(.headline)
                        .legibleForeground(.primary)
                    Spacer()
                    Text("\(saved.songs.count)")
                        .legibleForeground(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .legibleForeground(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The artist's most played songs, from the Catalog.
struct ArtistCatalogSongs: View {
    let tracks: [CatalogTrack]
    let onPlay: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            ArtistSectionHeader(title: "Top Songs")
                .padding(.bottom)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    onPlay(index)
                } label: {
                    TrackListItem(
                        trackName: track.title,
                        artistName: track.album.map { "\(track.artist) • \($0)" } ?? track.artist,
                        duration: track.durationSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "",
                        artworkURL: track.artworkURL,
                        isExplicit: track.isExplicit
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

/// The page's layout while the Catalog loads: a songs list and a shelf of covers, empty.
struct ArtistPageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading) {
                ArtistSectionHeader(title: "Top Songs")
                    .padding(.bottom)
                TrackListSkeleton(count: 5)
            }
            .padding()

            VStack(alignment: .leading) {
                ArtistSectionHeader(title: "Albums")
                    .padding(.horizontal)
                    .padding(.bottom)
                HStack(spacing: 24) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        SkeletonBox(cornerRadius: 0)
                            .frame(width: 175, height: 175)
                    }
                }
                .padding(.horizontal, 24)
                .shimmering()
            }
        }
        .transition(.opacity)
    }
}

/// The artist's bio, four lines until it is opened.
struct ArtistAbout: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtistSectionHeader(title: "About")

            Text(text)
                .font(.body)
                .legibleForeground(.secondary)
                .lineLimit(isExpanded ? nil : 4)

            Button(isExpanded ? "Less" : "More") {
                withAnimation(.snappy) { isExpanded.toggle() }
            }
            .font(.body.weight(.semibold))
            .legibleForeground(.primary)
            .buttonStyle(.plain)
        }
        .padding()
    }
}

extension RemoteAlbum {
    /// A Catalog album, its tracks fetched from YouTube Music or Apple's catalogue on open.
    init(_ album: CatalogAlbum, artist: String, catalog: Catalog?) {
        self.init(
            title: album.title,
            artist: album.artist ?? artist,
            year: album.year,
            artworkURL: album.artworkURL,
            sourceID: album.id,
            loadTracks: { await catalog?.albumTracks(album) ?? [] }
        )
    }
}

extension RemotePlaylist {
    /// A Catalog playlist, its tracks fetched from YouTube Music on open.
    init(_ playlist: CatalogPlaylist, catalog: Catalog?) {
        self.init(
            title: playlist.title,
            owner: playlist.owner,
            artworkURL: playlist.artworkURL,
            source: .youtubeMusic,
            sourceID: playlist.youtubeBrowseID,
            loadTracks: { await (catalog?.playlistTracks(youtubeBrowseID: playlist.youtubeBrowseID) ?? []).map(\.incoming) }
        )
    }
}
