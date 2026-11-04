package aaravgupta.cisum.ui.screens.home

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.repository.CatalogRepository
import aaravgupta.cisum.data.repository.ListeningHistory
import aaravgupta.cisum.playback.PlaybackCoordinator
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import aaravgupta.cisum.data.remote.swift.toTrack
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** HomeViewModel.swift: Top Songs and Trending from YouTube charts. "Jump Back In" is the history. */
@HiltViewModel
class HomeViewModel @Inject constructor(
    private val catalog: CatalogRepository,
    history: ListeningHistory,
    private val playback: PlaybackCoordinator,
) : ViewModel() {
    /** "Jump Back In": the last 15 plays. */
    val jumpBackIn = history.entries.map { it.take(15) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Plays [track] with the rest of its section queued, like iOS playing from a shelf. */
    fun play(track: Track, section: List<Track>) = playback.play(track, section)

    data class UiState(
        val topSongs: List<Track> = emptyList(),
        val trending: List<Track> = emptyList(),
        val isLoading: Boolean = false,
        val errorMessage: String? = null,
    )

    private val state = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = state.asStateFlow()

    init { refresh() }

    fun refresh(force: Boolean = false) {
        state.value = state.value.copy(isLoading = true, errorMessage = null)
        viewModelScope.launch {
            val top = async { runCatching { catalog.charts("topSongs", force = force).map { it.toTrack() } } }
            val trending = async { runCatching { catalog.charts("trending", force = force).map { it.toTrack() } } }
            val t = top.await(); val tr = trending.await()
            state.value = UiState(
                topSongs = t.getOrDefault(emptyList()),
                trending = tr.getOrDefault(emptyList()),
                isLoading = false,
                errorMessage = if (t.isFailure && tr.isFailure) t.exceptionOrNull()?.message else null,
            )
        }
    }
}
