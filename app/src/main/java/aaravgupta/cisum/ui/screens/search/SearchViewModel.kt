package aaravgupta.cisum.ui.screens.search

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.remote.swift.MusicArtist
import aaravgupta.cisum.data.remote.swift.MusicPlaylist
import aaravgupta.cisum.data.repository.CatalogRepository
import aaravgupta.cisum.playback.PlaybackCoordinator
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * SearchViewModel.swift, YouTube Music side: songs, artists and playlists for a query, debounced as
 * the user types, plus recent searches. ponytail: Spotify / Apple Music federation and the
 * ranking (CandidateRanking, SongMatcher) are not ported; results are YouTube Music's order.
 */
@HiltViewModel
class SearchViewModel @Inject constructor(
    private val catalog: CatalogRepository,
    private val playback: PlaybackCoordinator,
) : ViewModel() {
    /** Plays a result with the other song results queued after it. */
    fun play(track: Track) {
        val songs = (_state.value as? State.Success)?.songs.orEmpty()
        playback.play(track, if (songs.any { it.id == track.id }) songs else listOf(track))
    }

    sealed interface State {
        data object Idle : State
        data object Loading : State
        data class Error(val message: String) : State
        data class Success(val songs: List<Track>, val artists: List<MusicArtist>, val playlists: List<MusicPlaylist>) : State
    }

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()
    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()
    private val _recent = MutableStateFlow<List<String>>(emptyList())
    val recentSearches: StateFlow<List<String>> = _recent.asStateFlow()
    private val _suggestions = MutableStateFlow<List<String>>(emptyList())
    val suggestions: StateFlow<List<String>> = _suggestions.asStateFlow()

    private var job: Job? = null

    fun onQueryChange(text: String) {
        _query.value = text
        job?.cancel()
        if (text.isBlank()) { _state.value = State.Idle; _suggestions.value = emptyList(); return }
        job = viewModelScope.launch {
            delay(350)
            _suggestions.value = runCatching { catalog.suggestions(text) }.getOrDefault(emptyList())
            run(text)
        }
    }

    fun submit(text: String = _query.value) {
        if (text.isBlank()) return
        _query.value = text
        _suggestions.value = emptyList()
        _recent.value = (listOf(text) + _recent.value.filterNot { it == text }).take(20)
        job?.cancel()
        job = viewModelScope.launch { run(text) }
    }

    fun removeRecent(text: String) { _recent.value = _recent.value - text }

    fun clear() { job?.cancel(); _query.value = ""; _suggestions.value = emptyList(); _state.value = State.Idle }

    private suspend fun run(text: String) {
        _state.value = State.Loading
        val songs = viewModelScope.async { runCatching { catalog.searchSongs(text) } }
        val artists = viewModelScope.async { runCatching { catalog.searchArtists(text) } }
        val playlists = viewModelScope.async { runCatching { catalog.searchPlaylists(text) } }
        val s = songs.await(); val a = artists.await(); val p = playlists.await()
        _state.value = if (s.isFailure && a.isFailure && p.isFailure) {
            State.Error(s.exceptionOrNull()?.message ?: "Search failed")
        } else {
            State.Success(s.getOrDefault(emptyList()), a.getOrDefault(emptyList()), p.getOrDefault(emptyList()))
        }
    }
}
