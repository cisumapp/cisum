package aaravgupta.cisum.data.remote.youtube

import aaravgupta.cisum.data.model.Track
// import aaravgupta.youtubesdk.YouTube
// import aaravgupta.youtubesdk.youtube.models.YouTubeContinuation as Continuation
// import aaravgupta.youtubesdk.youtube.models.YouTubeItem

class YouTubeClient(
    private val youTube: Any? = null, // YouTube
    private val fallbackStreamUrl: String = FALLBACK_STREAM_URL
) {
    suspend fun getHome(
        regionCode: String = "US",
        languageCode: String = "en",
        musicOnly: Boolean = false
    ): YouTubeContinuation<Track> {
        return YouTubeContinuation(items = emptyList(), continuationToken = null) // TODO stub
        /*
        return runCatching {
            youTube.main.getHome(
                regionCode = regionCode,
                languageCode = languageCode,
                musicOnly = musicOnly
            ).toTrackContinuation()
        }.getOrElse {
            YouTubeContinuation(items = emptyList(), continuationToken = null)
        }
        */
    }

    suspend fun search(
        query: String,
        regionCode: String = "US",
        languageCode: String = "en",
        params: String? = null
    ): YouTubeContinuation<Track> {
        return YouTubeContinuation(items = emptyList(), continuationToken = null) // TODO stub
        /*
        return runCatching {
            youTube.main.search(query).toTrackContinuation()
        }.getOrElse {
            YouTubeContinuation(items = emptyList(), continuationToken = null)
        }
        */
    }

    suspend fun fetchContinuation(
        continuationToken: String,
        regionCode: String = "US",
        languageCode: String = "en"
    ): YouTubeContinuation<Track> {
        return YouTubeContinuation(items = emptyList(), continuationToken = null) // TODO stub
        /*
        return runCatching {
            youTube.main.fetchContinuation(token = continuationToken).toTrackContinuation()
        }.getOrElse {
            YouTubeContinuation(items = emptyList(), continuationToken = null)
        }
        */
    }

    suspend fun resolveStreamUrl(
        videoId: String,
        regionCode: String = "US",
        languageCode: String = "en"
    ): String? {
        return null // TODO stub
        /*
        return runCatching {
            YouTubeTrackMapper.resolvePreferredStream(youTube.main.video(videoId))
        }.getOrNull()
        */
    }

    /*
    private fun Continuation<YouTubeItem>.toTrackContinuation(): YouTubeContinuation<Track> {
        return YouTubeContinuation(
            items = items
                .flatMap { item ->
                    YouTubeTrackMapper.itemToTracks(
                        item = item,
                        fallbackStreamUrl = fallbackStreamUrl
                    )
                }
                .distinctBy { track -> track.id },
            continuationToken = continuationToken
        )
    }
    */

    companion object {
        const val FALLBACK_STREAM_URL: String =
            "https://storage.googleapis.com/exoplayer-test-media-0/play.mp3"
    }
}