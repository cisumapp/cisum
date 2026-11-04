package aaravgupta.cisum.data.repository

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.remote.youtube.YouTubeClient
import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.domain.repository.TrackPage
import aaravgupta.cisum.swift.SwiftBridge
import android.util.Log
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class InMemoryMusicRepository(
    private val youTubeClient: YouTubeClient,
    history: ListeningHistory,
) : MusicRepository {
    private val sampleStreamUrl = YouTubeClient.FALLBACK_STREAM_URL
    private var homeContinuationToken: String? = null
    private var searchContinuationToken: String? = null
    private var activeSearchQuery: String = ""
    private var activeSearchResults: List<Track> = emptyList()

    private val fallbackTracks = listOf(
        Track(
            id = "yt-track-001",
            title = "Northern Lights",
            artist = "Cisum Radio",
            artworkUrl = null,
            durationMs = 206_000,
            streamUrl = sampleStreamUrl
        ),
        Track(
            id = "yt-track-002",
            title = "Midnight Transit",
            artist = "The Echoed",
            artworkUrl = null,
            durationMs = 228_000,
            streamUrl = sampleStreamUrl
        ),
        Track(
            id = "yt-track-003",
            title = "Parallel Dreams",
            artist = "Aster Vale",
            artworkUrl = null,
            durationMs = 192_000,
            streamUrl = sampleStreamUrl
        ),
        Track(
            id = "yt-track-004",
            title = "Glass Ocean",
            artist = "Noon Theory",
            artworkUrl = null,
            durationMs = 214_000,
            streamUrl = sampleStreamUrl
        )
    )

    private val tracksState = MutableStateFlow(fallbackTracks)
    // Like iOS: the mini player comes back with the last song played, or stays hidden.
    private val nowPlayingState = MutableStateFlow<Track?>(history.entries.value.firstOrNull())

    override fun tracks(): Flow<List<Track>> = tracksState

    override val nowPlaying: StateFlow<Track?> = nowPlayingState.asStateFlow()

    override suspend fun refreshHome(): Boolean {
        val homeContinuation = youTubeClient.getHome()
        val homeTracks = homeContinuation.items.distinctBy { track -> track.id }
        homeContinuationToken = homeContinuation.continuationToken

        if (homeTracks.isNotEmpty()) {
            tracksState.value = homeTracks
            if (nowPlayingState.value == null || homeTracks.none { track ->
                    track.id == nowPlayingState.value?.id
                }
            ) {
                nowPlayingState.value = homeTracks.first()
            }
        }

        return !homeContinuationToken.isNullOrBlank()
    }

    override suspend fun loadMoreHome(): Boolean {
        val continuationToken = homeContinuationToken
        if (continuationToken.isNullOrBlank()) {
            return false
        }

        val continuation = youTubeClient.fetchContinuation(continuationToken)
        homeContinuationToken = continuation.continuationToken

        if (continuation.items.isNotEmpty()) {
            tracksState.value = (tracksState.value + continuation.items)
                .distinctBy { track -> track.id }
        }

        return !homeContinuationToken.isNullOrBlank()
    }

    override suspend fun searchTracks(query: String): TrackPage {
        val normalizedQuery = query.trim()
        if (normalizedQuery.isEmpty()) {
            activeSearchQuery = ""
            searchContinuationToken = null
            activeSearchResults = tracksState.value
            return TrackPage(
                items = activeSearchResults,
                hasMore = false
            )
        }

        // Swift YouTubeSDK first; the Kotlin client stays as fallback and for continuations.
        val swiftTracks = runCatching { swiftSearch(normalizedQuery) }
            .onFailure { Log.w(TAG, "Swift search failed", it) }
            .getOrDefault(emptyList())
        if (swiftTracks.isNotEmpty()) {
            Log.i(TAG, "Swift search '$normalizedQuery' -> ${swiftTracks.size} tracks")
            activeSearchQuery = normalizedQuery
            searchContinuationToken = null
            activeSearchResults = swiftTracks
            return TrackPage(items = activeSearchResults, hasMore = false)
        }

        val searchedContinuation = youTubeClient.search(query = normalizedQuery)
        val searchedTracks = searchedContinuation.items.distinctBy { track -> track.id }

        return if (searchedTracks.isNotEmpty()) {
            activeSearchQuery = normalizedQuery
            searchContinuationToken = searchedContinuation.continuationToken
            activeSearchResults = searchedTracks
            TrackPage(
                items = activeSearchResults,
                hasMore = !searchContinuationToken.isNullOrBlank()
            )
        } else {
            activeSearchQuery = normalizedQuery
            searchContinuationToken = null
            activeSearchResults = localFilter(normalizedQuery)
            TrackPage(
                items = activeSearchResults,
                hasMore = false
            )
        }
    }

    override suspend fun loadMoreSearchResults(): TrackPage {
        if (activeSearchQuery.isBlank()) {
            return TrackPage(items = activeSearchResults, hasMore = false)
        }

        val continuationToken = searchContinuationToken
        if (continuationToken.isNullOrBlank()) {
            return TrackPage(
                items = activeSearchResults,
                hasMore = false
            )
        }

        val continuation = youTubeClient.fetchContinuation(continuationToken)
        searchContinuationToken = continuation.continuationToken

        if (continuation.items.isNotEmpty()) {
            activeSearchResults = (activeSearchResults + continuation.items)
                .distinctBy { track -> track.id }
        }

        return TrackPage(
            items = activeSearchResults,
            hasMore = !searchContinuationToken.isNullOrBlank()
        )
    }

    override suspend fun resolveTrackForPlayback(track: Track): Track {
        if (track.id.startsWith("itunes-")) {
            return track.copy(
                streamUrl = track.streamUrl.takeIf { url ->
                    url.isPlayableStreamUrl()
                } ?: sampleStreamUrl
            )
        }

        val swift = runCatching { SwiftBridge.youtubeResolve(track.id) }
            .onFailure { Log.w(TAG, "Swift resolve failed", it) }.getOrNull()
        fun field(k: String) = swift?.optString(k)?.takeIf { it.isNotEmpty() && it != "null" }
        val resolvedStreamUrl = field("url")?.also { Log.i(TAG, "Swift resolve ${track.id} -> ${it.take(80)}") }
            ?: runCatching { youTubeClient.resolveStreamUrl(track.id) }.getOrNull()

        val playableUrl = when {
            resolvedStreamUrl.isPlayableStreamUrl() -> resolvedStreamUrl.orEmpty()
            track.streamUrl.isPlayableStreamUrl() -> track.streamUrl
            else -> sampleStreamUrl
        }

        return track.copy(
            streamUrl = playableUrl,
            durationMs = track.durationMs.takeIf { it > 0 } ?: ((swift?.optDouble("duration", 0.0) ?: 0.0) * 1000).toLong(),
            sourceName = "YouTube Music",
            mimeType = field("mimeType"),
            codec = field("codec"),
        )
    }

    override fun setNowPlaying(track: Track) {
        nowPlayingState.value = track
        if (tracksState.value.none { existingTrack -> existingTrack.id == track.id }) {
            tracksState.value = listOf(track) + tracksState.value
        }
    }

    private fun localFilter(query: String): List<Track> {
        return tracksState.value.filter { track ->
            track.title.contains(query, ignoreCase = true) ||
                track.artist.contains(query, ignoreCase = true)
        }
    }

    private suspend fun swiftSearch(query: String): List<Track> {
        val results = SwiftBridge.youtubeSearch(query)
        return (0 until results.length()).map { i ->
            val song = results.getJSONObject(i)
            val artists = song.optJSONArray("artists")
            Track(
                id = song.getString("videoId"),
                title = song.getString("title"),
                artist = (0 until (artists?.length() ?: 0)).joinToString(", ") { artists!!.getString(it) },
                artworkUrl = song.optString("thumbnailURL").takeIf { it.isNotEmpty() },
                durationMs = (song.optDouble("duration", 0.0) * 1000).toLong(),
                streamUrl = sampleStreamUrl
            )
        }.distinctBy { it.id }
    }

    private companion object {
        const val TAG = "SwiftBridge"
    }

    private fun String?.isPlayableStreamUrl(): Boolean {
        val value = this?.trim().orEmpty()
        if (value.isBlank()) {
            return false
        }

        return value.startsWith("https://") || value.startsWith("http://")
    }
}
