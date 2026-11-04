package aaravgupta.cisum.service

import android.content.ComponentName
import android.content.Context
import aaravgupta.cisum.data.model.Track
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class PlaybackStateSnapshot(
    val isConnected: Boolean = false,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val currentTrackId: String? = null,
    val currentPositionMs: Long = 0L,
    val durationMs: Long = 0L,
    val volume: Float = 1f,
    val hasNext: Boolean = false,
    val hasPrevious: Boolean = false,
    val errorMessage: String? = null
)

class PlaybackController(
    context: Context
) {
    private val appContext = context.applicationContext
    private val pendingActions = mutableListOf<(MediaController) -> Unit>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var mediaController: MediaController? = null
    private var playerListener: Player.Listener? = null
    private var statePublisherJob: Job? = null

    private val _playbackState = MutableStateFlow(PlaybackStateSnapshot())
    val playbackState: StateFlow<PlaybackStateSnapshot> = _playbackState.asStateFlow()

    init {
        connectIfNeeded()
    }

    fun playTracks(queue: List<Track>, startTrackId: String) {
        if (queue.isEmpty()) {
            return
        }

        withController { controller ->
            val startIndex = queue.indexOfFirst { it.id == startTrackId }
                .let { if (it >= 0) it else 0 }

            controller.setMediaItems(
                queue.map { track -> track.toMediaItem() },
                startIndex,
                0L
            )
            controller.prepare()
            controller.play()
        }
    }

    fun togglePlayPause() {
        withController { controller ->
            if (controller.isPlaying) {
                controller.pause()
            } else {
                controller.play()
            }
        }
    }

    fun skipToNext() {
        withController { controller ->
            if (controller.hasNextMediaItem()) {
                controller.seekToNextMediaItem()
            }
        }
    }

    fun skipToPrevious() {
        withController { controller ->
            if (controller.hasPreviousMediaItem()) {
                controller.seekToPreviousMediaItem()
            } else {
                controller.seekTo(0L)
            }
        }
    }

    fun seekTo(positionMs: Long) {
        withController { controller ->
            controller.seekTo(positionMs.coerceAtLeast(0L))
            publishState(controller)
        }
    }

    fun setVolume(volume: Float) {
        withController { controller ->
            controller.volume = volume.coerceIn(0f, 1f)
            publishState(controller)
        }
    }

    fun release() {
        statePublisherJob?.cancel()
        statePublisherJob = null
        playerListener?.let { listener ->
            mediaController?.removeListener(listener)
        }
        playerListener = null
        mediaController = null
        controllerFuture?.let { future ->
            MediaController.releaseFuture(future)
        }
        controllerFuture = null
        _playbackState.value = PlaybackStateSnapshot()
    }

    private fun withController(action: (MediaController) -> Unit) {
        val existingController = mediaController
        if (existingController != null) {
            action(existingController)
            return
        }

        pendingActions += action
        connectIfNeeded()
    }

    @Synchronized
    private fun connectIfNeeded() {
        if (mediaController != null || controllerFuture != null) {
            return
        }

        val sessionToken = SessionToken(
            appContext,
            ComponentName(appContext, MediaPlaybackService::class.java)
        )

        val future = MediaController.Builder(appContext, sessionToken)
            .buildAsync()
        controllerFuture = future

        future.addListener(
            {
                val createdController = runCatching { future.get() }
                    .getOrNull()

                if (createdController == null) {
                    _playbackState.value = PlaybackStateSnapshot(isConnected = false)
                    controllerFuture = null
                    return@addListener
                }

                attachController(createdController)
            },
            ContextCompat.getMainExecutor(appContext)
        )
    }

    private fun attachController(controller: MediaController) {
        mediaController = controller

        val listener = object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) {
                publishState(player)
            }

            override fun onPlayerError(error: PlaybackException) {
                _playbackState.value = _playbackState.value.copy(
                    errorMessage = formatPlaybackError(error)
                )
            }
        }

        playerListener = listener
        controller.addListener(listener)
        publishState(controller)
        startStatePublisher(controller)

        val queuedActions = pendingActions.toList()
        pendingActions.clear()
        queuedActions.forEach { pendingAction ->
            pendingAction(controller)
        }
    }

    private fun startStatePublisher(controller: MediaController) {
        statePublisherJob?.cancel()
        statePublisherJob = scope.launch {
            while (isActive) {
                publishState(controller)
                delay(if (controller.isPlaying) 250L else 750L)
            }
        }
    }

    private fun publishState(player: Player) {
        val playerDuration = player.duration
        val resolvedDuration = if (playerDuration > 0L) {
            playerDuration
        } else {
            0L
        }

        _playbackState.value = PlaybackStateSnapshot(
            isConnected = true,
            isPlaying = player.isPlaying,
            isBuffering = player.playbackState == Player.STATE_BUFFERING,
            currentTrackId = player.currentMediaItem?.mediaId,
            currentPositionMs = player.currentPosition.coerceAtLeast(0L),
            durationMs = resolvedDuration,
            volume = player.volume.coerceIn(0f, 1f),
            hasNext = player.hasNextMediaItem(),
            hasPrevious = player.hasPreviousMediaItem(),
            errorMessage = player.playerError?.let(::formatPlaybackError)
        )
    }

    private fun formatPlaybackError(error: PlaybackException): String {
        return listOfNotNull(
            error.errorCodeName.takeIf { it.isNotBlank() },
            error.message,
            error.cause?.message
        )
            .distinct()
            .joinToString(" • ")
            .ifBlank { "Playback failed" }
    }
}

private val youTubeId = Regex("^[A-Za-z0-9_-]{11}$")

private fun Track.toMediaItem(): MediaItem {
    return MediaItem.Builder()
        .setMediaId(id)
        // YouTube tracks are resolved by the player when it opens them (StreamUrlResolver);
        // anything else (an iTunes preview) already has its URL.
        .setUri(if (youTubeId.matches(id)) aaravgupta.cisum.service.stream.StreamUrlResolver.uriFor(id) else android.net.Uri.parse(streamUrl))
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .build()
        )
        .build()
}