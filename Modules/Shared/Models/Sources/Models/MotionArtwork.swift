//
//  MotionArtwork.swift
//  Models
//
//  Animated artwork (Spotify Canvas, Apple Music motion artwork) as the views see it: a track to
//  ask about, and a local video file once one has been downloaded. Where the videos come from is
//  the Catalog's business, so the player and the cards depend on this alone.
//

import Foundation
import SwiftUI

/// The track or album an animated artwork is wanted for.
public struct MotionArtworkRequest: Sendable, Hashable {
    public let title: String
    public let artist: String
    public let album: String?
    /// Lets Spotify's Canvas be tried first, when the user is signed in to Spotify.
    public let spotifyTrackID: String?

    public init(title: String, artist: String, album: String? = nil, spotifyTrackID: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.spotifyTrackID = spotifyTrackID
    }
}

/// Looks up and downloads animated artwork, kept on the device for later plays.
public struct MotionArtworkSource: Sendable {
    /// The downloaded video for this request, if there is one. Cheap: a file check.
    public let cachedVideo: @Sendable (MotionArtworkRequest) -> URL?
    /// Downloads the video if one exists and returns the local file.
    public let fetch: @Sendable (MotionArtworkRequest) async -> URL?

    public init(
        cachedVideo: @escaping @Sendable (MotionArtworkRequest) -> URL?,
        fetch: @escaping @Sendable (MotionArtworkRequest) async -> URL?
    ) {
        self.cachedVideo = cachedVideo
        self.fetch = fetch
    }
}

public extension EnvironmentValues {
    @Entry var motionArtwork: MotionArtworkSource?
}
