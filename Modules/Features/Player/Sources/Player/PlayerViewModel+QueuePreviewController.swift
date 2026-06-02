import Foundation
import Models
import Utilities
import YouTubeSDK

extension PlayerViewModel {
    public struct QueuePreviewItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let artworkURL: URL?

        public init(id: String, title: String, subtitle: String, artworkURL: URL?) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.artworkURL = artworkURL
        }
    }

    var currentQueuePreviewIndex: Int? {
        queuePosition
    }

    var previousQueuePreviewItem: QueuePreviewItem? {
        guard let queuePosition,
              queuePosition > 0,
              queuePreviewItems.indices.contains(queuePosition - 1)
        else {
            return nil
        }

        return queuePreviewItems[queuePosition - 1]
    }

    var nextQueuePreviewItem: QueuePreviewItem? {
        guard let queuePosition,
              queuePreviewItems.indices.contains(queuePosition + 1)
        else {
            return nil
        }

        return queuePreviewItems[queuePosition + 1]
    }

    func updateQueuePreviewItems() {
        let entries = playbackQueue
        Task { [weak self] in
            guard let self else { return }
            let items = await mapQueueEntriesToPreview(entries)
            await MainActor.run {
                self.queuePreviewItems = items
            }
        }
    }

    nonisolated func mapQueueEntriesToPreview(_ entries: [PlaybackQueueEntry]) async -> [QueuePreviewItem] {
        entries.enumerated().map { index, entry in
            switch entry {
            case let .song(song):
                QueuePreviewItem(
                    id: "\(index)-\(song.videoId)",
                    title: normalizedMusicDisplayTitle(song.title, artist: song.artistsDisplay),
                    subtitle: normalizedMusicDisplayArtist(song.artistsDisplay, title: song.title),
                    artworkURL: song.thumbnailURL
                )
            case let .video(video):
                QueuePreviewItem(
                    id: "\(index)-\(video.id)",
                    title: normalizedMusicDisplayTitle(video.title, artist: video.author),
                    subtitle: normalizedMusicDisplayArtist(video.author, title: video.title),
                    artworkURL: normalizedArtworkURL(from: video.thumbnailURL)
                )
            case let .cachedRadio(track):
                QueuePreviewItem(
                    id: "\(index)-\(track.videoID)",
                    title: normalizedMusicDisplayTitle(track.title, artist: track.artist),
                    subtitle: normalizedMusicDisplayArtist(track.artist, title: track.title),
                    artworkURL: track.thumbnailURL
                )
            case let .external(track):
                QueuePreviewItem(
                    id: "\(index)-\(track.mediaID)",
                    title: normalizedMusicDisplayTitle(track.title, artist: track.artist),
                    subtitle: normalizedMusicDisplayArtist(track.artist, title: track.title),
                    artworkURL: track.artworkURL
                )
            }
        }
    }
}
