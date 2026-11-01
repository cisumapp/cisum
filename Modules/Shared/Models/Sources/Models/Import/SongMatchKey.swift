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

    /// The canonical record's **un-normalised** title, when the caller has it.
    ///
    /// `normalizedTitle` has version markers stripped, so version inference needs the raw title to
    /// see them. When absent, `normalizedTitle` is used and inference degrades to `.original`.
    public let title: String?

    /// Structured version evidence for the canonical record, when available.
    ///
    /// No producer sets this yet — the canonical store has no structured version column — so in
    /// production the version gate falls back to title inference on both sides. It exists so a
    /// reporting pipeline (or a test) can supply reported evidence without changing the key shape.
    public let versionEvidence: VersionEvidence?

    public init(
        songID: String,
        normalizedTitle: String,
        artistName: String? = nil,
        durationSeconds: Double? = nil,
        albumName: String? = nil,
        title: String? = nil,
        versionEvidence: VersionEvidence? = nil
    ) {
        self.songID = songID
        self.normalizedTitle = normalizedTitle
        self.artistName = artistName
        self.durationSeconds = durationSeconds
        self.albumName = albumName
        self.title = title
        self.versionEvidence = versionEvidence
    }
}
