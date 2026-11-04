package aaravgupta.cisum.ui.screens.discover

import aaravgupta.cisum.data.remote.swift.ChartItem
import aaravgupta.cisum.data.remote.swift.toTrack
import aaravgupta.cisum.data.repository.CatalogRepository
import aaravgupta.cisum.playback.PlaybackCoordinator
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DiscoverSection(val id: String, val title: String, val subtitle: String, val items: List<ChartItem>)

/** DiscoverView.loadDiscoverSections: the four YouTube charts, ten items each. */
@HiltViewModel
class DiscoverViewModel @Inject constructor(
    private val catalog: CatalogRepository,
    private val playback: PlaybackCoordinator,
) : ViewModel() {
    /** Plays a chart entry with the playable rest of its chart queued. */
    fun play(item: ChartItem, section: DiscoverSection) =
        playback.play(item.toTrack(), section.items.filter { it.type == "song" || it.type == "video" }.map { it.toTrack() })

    data class UiState(val sections: List<DiscoverSection> = emptyList(), val isLoading: Boolean = true, val errorMessage: String? = null)

    private val state = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = state.asStateFlow()

    init { refresh() }

    fun refresh() {
        state.value = state.value.copy(isLoading = true)
        viewModelScope.launch {
            val specs = listOf(
                Triple("topSongs", "Top Songs", "YouTube Music"),
                Triple("topVideos", "Top Videos", "YouTube"),
                Triple("topArtists", "Top Artists", "YouTube Music"),
                Triple("trending", "Trending", "YouTube"),
            )
            val results = specs.map { (kind, title, sub) ->
                async { runCatching { DiscoverSection(kind, title, sub, catalog.charts(kind).take(10)) } }
            }.awaitAll()
            val sections = results.mapNotNull { it.getOrNull() }.filter { it.items.isNotEmpty() }
            state.value = UiState(
                sections = sections,
                isLoading = false,
                errorMessage = if (sections.isEmpty()) results.firstNotNullOfOrNull { it.exceptionOrNull()?.message } ?: "No chart data was returned." else null,
            )
        }
    }
}
