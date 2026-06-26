//
//  YouTubeMediaRef+YouTube.swift
//  cisum
//
//  Convenience bridges from YouTubeSDK types to the neutral `YouTubeMediaRef` (Models).
//  Lives in Player (a YouTube-aware module imported by every feature) so call sites can
//  build a neutral ref from a raw YouTube object in one line.
//

import Foundation
import Models
import YouTubeSDK

public extension YouTubeMediaRef {
    init(song: YouTubeMusicSong) {
        self.init(
            videoID: song.videoId,
            title: song.title,
            artist: song.artistsDisplay,
            album: song.album,
            artworkURL: song.thumbnailURL,
            durationSeconds: song.duration,
            isExplicit: song.isExplicit,
            isMusic: true
        )
    }

    init(video: YouTubeVideo) {
        self.init(
            videoID: video.id,
            title: video.title,
            artist: video.author,
            artworkURL: video.thumbnailURL.flatMap { URL(string: $0) },
            durationSeconds: Double(video.lengthInSeconds),
            isExplicit: false,
            isMusic: false,
            viewCount: video.viewCount
        )
    }
}
