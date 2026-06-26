//
//  ImportDTOs.swift
//  Models
//
//  Provider-neutral DTOs shared across the import service layer and the Download Manager.
//  No SDK import — keeps Models a dependency leaf.
//

import Foundation

/// The import sources surfaced to the user. Maps to `MediaProvider` at the service boundary.
public enum ImportProvider: String, Sendable, CaseIterable, Hashable {
    case spotify
    case youtube
    case appleMusic
    case localFile
}

/// What a given `ImportService` is able to do. UI reads these to decide which affordances to show.
public struct ImportCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let listsUserPlaylists = ImportCapabilities(rawValue: 1 << 0)
    public static let importByLink       = ImportCapabilities(rawValue: 1 << 1)
    public static let likedSongs         = ImportCapabilities(rawValue: 1 << 2)
    public static let carriesISRC        = ImportCapabilities(rawValue: 1 << 3)
}

/// A playlist (or synthetic collection, e.g. a local-file selection) the user can choose to import.
public struct ImportablePlaylistRef: Identifiable, Sendable, Hashable {
    public let id: String                 // provider playlist id / encoded file bookmark
    public let title: String
    public let subtitle: String?
    public let ownerName: String?
    public let artworkURL: URL?
    public let trackCount: Int?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        ownerName: String? = nil,
        artworkURL: URL? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.ownerName = ownerName
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }
}

/// Playlist header metadata, fetched before paging through its tracks.
public struct ImportPlaylistMetadata: Sendable {
    public let sourcePlaylistID: String
    public let title: String
    public let ownerName: String?
    public let descriptionText: String?
    public let artworkURL: URL?
    public let sourceURLString: String?
    public let totalTrackCount: Int?

    public init(
        sourcePlaylistID: String,
        title: String,
        ownerName: String? = nil,
        descriptionText: String? = nil,
        artworkURL: URL? = nil,
        sourceURLString: String? = nil,
        totalTrackCount: Int? = nil
    ) {
        self.sourcePlaylistID = sourcePlaylistID
        self.title = title
        self.ownerName = ownerName
        self.descriptionText = descriptionText
        self.artworkURL = artworkURL
        self.sourceURLString = sourceURLString
        self.totalTrackCount = totalTrackCount
    }
}

/// One page of neutral tracks. Cursor-based so the Download Manager can checkpoint/resume.
public struct ImportTrackPage: Sendable {
    public let tracks: [IncomingTrack]
    public let nextCursor: String?        // persisted as job.resumeToken; nil = last page
    public let startOffset: Int           // persisted as job.nextTrackOffset

    public init(tracks: [IncomingTrack], nextCursor: String?, startOffset: Int) {
        self.tracks = tracks
        self.nextCursor = nextCursor
        self.startOffset = startOffset
    }
}
