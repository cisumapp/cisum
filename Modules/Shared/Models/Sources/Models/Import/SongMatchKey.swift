//
//  SongMatchKey.swift
//  Models
//
//  Scalar projection of a canonical Song used for fuzzy comparison without holding the @Model.
//

import Foundation

public struct SongMatchKey: Sendable {
    public let songID: String
    public let normalizedTitle: String
    public let artistName: String?
    public let durationSeconds: Double?
    public let albumName: String?

    public init(
        songID: String,
        normalizedTitle: String,
        artistName: String? = nil,
        durationSeconds: Double? = nil,
        albumName: String? = nil
    ) {
        self.songID = songID
        self.normalizedTitle = normalizedTitle
        self.artistName = artistName
        self.durationSeconds = durationSeconds
        self.albumName = albumName
    }
}
