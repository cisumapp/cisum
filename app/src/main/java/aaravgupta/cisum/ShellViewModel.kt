package aaravgupta.cisum

import aaravgupta.cisum.data.repository.ListeningHistory
import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.playback.PlaybackCoordinator
import aaravgupta.cisum.service.PlaybackController
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

/** RootView's state: the mini player's track and transport, and requests to open the player. */
@HiltViewModel
class ShellViewModel @Inject constructor(
    private val repository: MusicRepository,
    private val controller: PlaybackController,
    playback: PlaybackCoordinator,
    history: ListeningHistory,
) : ViewModel() {
    val nowPlaying = repository.nowPlaying
    val playbackState = controller.playbackState
    val expandRequests = playback.expandRequests

    init {
        // Like iOS, the mini player comes back with the last song played once history has loaded.
        viewModelScope.launch {
            val last = history.entries.first { it.isNotEmpty() }.first()
            if (repository.nowPlaying.value == null) repository.setNowPlaying(last)
        }
    }

    fun togglePlayPause() = controller.togglePlayPause()
    fun skipToNext() = controller.skipToNext()
    fun skipToPrevious() = controller.skipToPrevious()
}
