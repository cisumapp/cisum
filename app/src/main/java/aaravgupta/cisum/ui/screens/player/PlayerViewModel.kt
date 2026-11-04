package aaravgupta.cisum.ui.screens.player

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.service.PlaybackController
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class PlayerUiState(
    val nowPlaying: Track? = null,
    val isPlaying: Boolean = false,
    val playbackPositionMs: Long = 0L,
    val playbackDurationMs: Long = 0L,
    val volume: Float = 1f,
    val canSkipNext: Boolean = false,
    val canSkipPrevious: Boolean = false,
    val isExplicit: Boolean = false,
    val streamingServiceName: String = "",
    val audioQualityLabel: String = "",
    val audioCodecLabel: String = "",
    val isConnected: Boolean = false,
    val playbackError: String? = null
)

@HiltViewModel
class PlayerViewModel @Inject constructor(
    musicRepository: MusicRepository,
    private val playbackController: PlaybackController
) : ViewModel() {
    /** Position ticks every 250 ms; only the scrubber reads it, so the rest of the player stays put. */
    val positionMs = playbackController.playbackState
        .map { it.currentPositionMs.coerceAtLeast(0L) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0L)

    val uiState = combine(
        musicRepository.tracks(),
        musicRepository.nowPlaying,
        playbackController.playbackState.map { it.copy(currentPositionMs = 0L) }.distinctUntilChanged()
    ) { tracks, fallbackTrack, playbackState ->
        // The resolved now-playing track carries the stream details; the list copy does not.
        val nowPlaying = fallbackTrack?.takeIf { it.id == playbackState.currentTrackId || playbackState.currentTrackId == null }
            ?: tracks.firstOrNull { track -> track.id == playbackState.currentTrackId }
            ?: fallbackTrack

        val resolvedDuration = when {
            playbackState.durationMs > 0L -> playbackState.durationMs
            nowPlaying?.durationMs != null -> nowPlaying.durationMs
            else -> 0L
        }

        val resolvedPosition = playbackState.currentPositionMs
            .coerceAtLeast(0L)
            .coerceAtMost(resolvedDuration.takeIf { it > 0L } ?: Long.MAX_VALUE)

        val streamDetails = nowPlaying.toStreamDetails()

        PlayerUiState(
            nowPlaying = nowPlaying,
            isPlaying = playbackState.isPlaying,
            playbackPositionMs = resolvedPosition,
            playbackDurationMs = resolvedDuration,
            volume = playbackState.volume,
            canSkipNext = playbackState.hasNext,
            canSkipPrevious = playbackState.hasPrevious,
            isExplicit = nowPlaying?.isExplicit == true || nowPlaying.isLikelyExplicit(),
            streamingServiceName = streamDetails.serviceName,
            audioQualityLabel = streamDetails.qualityLabel,
            audioCodecLabel = streamDetails.codecLabel,
            isConnected = playbackState.isConnected,
            playbackError = playbackState.errorMessage
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = PlayerUiState()
    )

    fun togglePlayback() {
        playbackController.togglePlayPause()
    }

    fun skipToNext() {
        playbackController.skipToNext()
    }

    fun skipToPrevious() {
        playbackController.skipToPrevious()
    }

    fun seekTo(positionMs: Long) {
        playbackController.seekTo(positionMs)
    }

    fun setVolume(volume: Float) {
        playbackController.setVolume(volume)
    }
}

private data class StreamDetails(
    val serviceName: String,
    val qualityLabel: String,
    val codecLabel: String
)

private fun Track?.toStreamDetails(): StreamDetails {
    if (this == null) {
        return StreamDetails(
            serviceName = "Unknown Service",
            qualityLabel = "Unknown",
            codecLabel = "Unknown"
        )
    }

    // Resolution knows exactly what is playing; the URL guesses below are the fallback.
    if (sourceName != null) {
        return StreamDetails(serviceName = sourceName, qualityLabel = mimeType.orEmpty(), codecLabel = codec.orEmpty())
    }

    val normalizedUrl = streamUrl.lowercase()
    val serviceName = when {
        id.startsWith("itunes-") -> "Apple Music"
        id.startsWith("tidal-") -> "TIDAL"
        id.startsWith("yt-") || normalizedUrl.contains("youtube") || normalizedUrl.contains("googlevideo") -> "YouTube Music"
        normalizedUrl.contains("tidal") -> "TIDAL"
        normalizedUrl.contains("apple") || normalizedUrl.contains("itunes") -> "Apple Music"
        else -> "Streaming"
    }

    val qualityLabel = when {
        normalizedUrl.endsWith(".m3u8") || normalizedUrl.contains("m3u8") -> "Adaptive"
        id.startsWith("itunes-") -> "Preview"
        normalizedUrl.contains("flac") || normalizedUrl.contains("lossless") -> "Lossless"
        else -> "High"
    }

    val codecLabel = when {
        normalizedUrl.contains("aac") -> "AAC"
        normalizedUrl.contains("opus") -> "Opus"
        normalizedUrl.contains("mp3") -> "MP3"
        normalizedUrl.contains("flac") -> "FLAC"
        normalizedUrl.contains("m3u8") -> "HLS"
        else -> "Audio"
    }

    return StreamDetails(
        serviceName = serviceName,
        qualityLabel = qualityLabel,
        codecLabel = codecLabel
    )
}

private fun Track?.isLikelyExplicit(): Boolean {
    val value = this ?: return false
    return value.title
        .lowercase()
        .contains("explicit")
}
