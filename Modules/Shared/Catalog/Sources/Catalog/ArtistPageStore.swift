//
//  ArtistPageStore.swift
//  Catalog
//
//  Artist pages kept on the device. Artists do not release every few minutes, so a page fetched
//  once serves every visit for a few days, and the ones the user has visited are refreshed
//  overnight rather than while they wait.
//

import Foundation
import Models
import SwiftData
import SwiftUI

@MainActor
public final class ArtistPageStore {
    /// How long a saved page is used before it is fetched again.
    public static let timeToLive: TimeInterval = 3 * 24 * 60 * 60

    /// The app's store, for the overnight refresh, which runs outside any view.
    public private(set) static var shared: ArtistPageStore?

    private let catalog: Catalog
    private let container: ModelContainer

    public init(catalog: Catalog, container: ModelContainer) {
        self.catalog = catalog
        self.container = container
        Self.shared = self
    }

    /// The page saved for this artist, if one has been fetched.
    public func savedPage(for artist: Artist) -> CatalogArtist? {
        artist.catalogPageData.flatMap { try? JSONDecoder().decode(CatalogArtist.self, from: $0) }
    }

    public func isStale(_ artist: Artist) -> Bool {
        guard let fetchedAt = artist.catalogFetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > Self.timeToLive
    }

    /// Fetches the page, saves it on the artist, and returns it.
    ///
    /// A lookup that found nothing (no network, an unknown name) is returned but not saved, so it
    /// never replaces a good page.
    @discardableResult
    public func refresh(_ artist: Artist) async -> CatalogArtist {
        let page = await catalog.artist(named: artist.displayName, youtubeBrowseID: artist.youtubeMusicBrowseID)
        if artist.youtubeMusicBrowseID == nil, let browseID = page.youtubeBrowseID {
            artist.youtubeMusicBrowseID = browseID
        }
        if let photo = page.photoURL {
            artist.bannerURLString = photo.absoluteString
        }
        if page.youtubeBrowseID != nil || !page.albums.isEmpty {
            artist.catalogPageData = try? JSONEncoder().encode(page)
            artist.catalogFetchedAt = .now
        }
        try? artist.modelContext?.save()
        return page
    }

    /// Refreshes the pages of visited artists that have gone stale, oldest first.
    public func refreshStale(limit: Int = 25) async {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Artist>(
            predicate: #Predicate<Artist> { $0.catalogFetchedAt != nil },
            sortBy: [SortDescriptor(\.catalogFetchedAt)]
        )
        let artists = (try? context.fetch(descriptor)) ?? []
        for artist in artists.filter(isStale).prefix(limit) {
            if Task.isCancelled { return }
            await refresh(artist)
        }
    }
}

public extension EnvironmentValues {
    @Entry var artistPageStore: ArtistPageStore?
}
