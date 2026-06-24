//
//  YouTubeMusicFilter.swift
//  cisum
//
//  §C de-inversion: these filters take YouTubeSDK types, so they belong in the
//  provider-aware Models layer rather than generic Utilities. The string-only
//  helpers they call (isLikelyMusicMetadata / isLikelyArtistChannelName) stay in
//  Utilities.
//

import Foundation
import Utilities
import YouTubeSDK

public nonisolated func shouldKeepMusicHomeItem(_ item: YouTubeItem) -> Bool {
    switch item {
    case .song:
        true
    case let .video(video):
        shouldKeepMusicVideoResult(video)
    case let .channel(channel):
        shouldKeepMusicChannel(channel)
    case let .playlist(playlist):
        shouldKeepMusicPlaylist(playlist)
    case let .shelf(shelf):
        isLikelyMusicMetadata(title: shelf.title, secondaryText: nil)
    }
}

public nonisolated func shouldKeepMusicVideoResult(_ video: YouTubeVideo) -> Bool {
    isLikelyMusicMetadata(title: video.title, secondaryText: video.author)
}

public nonisolated func shouldKeepMusicChannel(_ channel: YouTubeChannel) -> Bool {
    isLikelyArtistChannelName(channel.title)
}

public nonisolated func shouldKeepMusicPlaylist(_ playlist: YouTubePlaylist) -> Bool {
    isLikelyMusicMetadata(title: playlist.title, secondaryText: playlist.author)
}
