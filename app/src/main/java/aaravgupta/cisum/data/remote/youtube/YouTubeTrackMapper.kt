package aaravgupta.cisum.data.remote.youtube

import aaravgupta.cisum.data.model.Track
// import aaravgupta.youtubesdk.youtube.models.YouTubeItem
// import aaravgupta.youtubesdk.youtube.models.YouTubeVideo
// import aaravgupta.youtubesdk.youtubeMusic.models.YouTubeMusicSong

internal object YouTubeTrackMapper {
    /*
    fun itemToTracks(item: YouTubeItem, fallbackStreamUrl: String): List<Track> {
        return when (item) {
            is YouTubeItem.Video -> listOf(videoToTrack(item.value, fallbackStreamUrl))
            is YouTubeItem.Song -> listOf(songToTrack(item.value, fallbackStreamUrl))
            is YouTubeItem.Shelf -> item.value.items.flatMap { nestedItem ->
                itemToTracks(nestedItem, fallbackStreamUrl)
            }

            is YouTubeItem.Channel,
            is YouTubeItem.Playlist -> emptyList()
        }
    }

    fun resolvePreferredStream(video: YouTubeVideo): String? {
        return listOf(
            video.hlsUrl,
            video.bestAudioStream?.url,
            video.bestMuxedStream?.url
        ).firstOrNull { candidate ->
            candidate.isPlayableStreamUrl()
        }
    }

    fun songToTrack(song: YouTubeMusicSong, fallbackStreamUrl: String): Track {
        return Track(
            id = song.videoId,
            title = song.title,
            artist = song.artistsDisplay.ifBlank { "Unknown Artist" },
            artworkUrl = song.thumbnailUrl,
            durationMs = ((song.duration ?: 0.0) * 1_000.0).toLong(),
            streamUrl = fallbackStreamUrl
        )
    }

    private fun videoToTrack(video: YouTubeVideo, fallbackStreamUrl: String): Track {
        return Track(
            id = video.id,
            title = video.title,
            artist = video.author,
            artworkUrl = video.thumbnailUrl,
            durationMs = durationStringToMillis(video.lengthInSeconds),
            streamUrl = resolvePreferredStream(video) ?: fallbackStreamUrl
        )
    }

    private fun durationStringToMillis(rawValue: String?): Long {
        val normalized = rawValue?.trim().orEmpty()
        if (normalized.isEmpty()) {
            return 0L
        }

        if (normalized.all { character -> character.isDigit() }) {
            return normalized.toLongOrNull()?.times(1_000L) ?: 0L
        }

        val parts = normalized
            .split(':')
            .map { part -> part.trim() }
            .map { part -> part.toLongOrNull() ?: return 0L }

        var totalSeconds = 0L
        for (part in parts) {
            totalSeconds = (totalSeconds * 60L) + part
        }

        return totalSeconds * 1_000L
    }

    private fun String?.isPlayableStreamUrl(): Boolean {
        val value = this?.trim().orEmpty()
        if (value.isEmpty()) {
            return false
        }

        return value.startsWith("https://") || value.startsWith("http://")
    }
    */
}
