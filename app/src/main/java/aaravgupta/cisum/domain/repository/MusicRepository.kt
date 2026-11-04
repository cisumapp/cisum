package aaravgupta.cisum.domain.repository

import aaravgupta.cisum.data.model.Track
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface MusicRepository {
    fun tracks(): Flow<List<Track>>

    val nowPlaying: StateFlow<Track?>

    suspend fun refreshHome(): Boolean

    suspend fun loadMoreHome(): Boolean

    suspend fun searchTracks(query: String): TrackPage

    suspend fun loadMoreSearchResults(): TrackPage

    suspend fun resolveTrackForPlayback(track: Track): Track

    fun setNowPlaying(track: Track)
}
