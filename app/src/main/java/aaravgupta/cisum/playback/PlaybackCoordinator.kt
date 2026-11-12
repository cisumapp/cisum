package aaravgupta.cisum.playback

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.repository.ListeningHistory
import aaravgupta.cisum.di.ApplicationScope
import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.service.PlaybackController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * iOS's `playbackCommands.load(_, preserveQueue: false)` plus `playerPresentationController.expand()`:
 * resolve through Swift, record the play, hand the stream to Media3, open the player.
 */
@Singleton
class PlaybackCoordinator @Inject constructor(
    private val repository: MusicRepository,
    private val controller: PlaybackController,
    private val history: ListeningHistory,
    private val streams: aaravgupta.cisum.service.stream.StreamUrlResolver,
    @ApplicationScope private val scope: CoroutineScope,
) {
    private val expand = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val expandRequests: SharedFlow<Unit> = expand.asSharedFlow()

    /** What the player was last given. It moves through this on its own. */
    @Volatile private var queue: List<Track> = emptyList()

    init {
        // A track ending, next / previous, and the notification's buttons all change the track
        // without going through play(). Follow the player, or the screen keeps showing the track
        // that was tapped.
        scope.launch {
            controller.playbackState.map { it.currentTrackId }.distinctUntilChanged().collect { id ->
                val track = queue.firstOrNull { it.id == id } ?: return@collect
                if (repository.nowPlaying.value?.id != id) {
                    repository.setNowPlaying(track)
                    history.record(track)
                }
            }
        }
    }

    /**
     * Plays [track], with [queue] around it for next / previous. Nothing is resolved up front: the
     * resolve starts now, in parallel with the player connecting, and the player picks it up when it
     * opens the item; the rest of the queue resolves when it is reached.
     */
    fun play(track: Track, queue: List<Track> = listOf(track), openPlayer: Boolean = true) {
        aaravgupta.cisum.perf.Perf.playRequestedAt = android.os.SystemClock.elapsedRealtime()
        if (openPlayer) expand.tryEmit(Unit)
        streams.prefetch(track.id)
        this.queue = queue.ifEmpty { listOf(track) }
        repository.setNowPlaying(track)
        history.record(track)
        scope.launch(Dispatchers.Main) { // MediaController is main-thread only
            controller.playTracks(queue.ifEmpty { listOf(track) }, track.id)
        }
    }
}
