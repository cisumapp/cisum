package aaravgupta.cisum.ui.screens.home

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.ui.components.HorizontalTrackSection
import aaravgupta.cisum.ui.components.NavigationBarView
import aaravgupta.cisum.ui.components.StatusMessage
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.navigation.compose.hiltViewModel

/** HomeView.swift */
@Composable
fun HomeScreen(onProfile: () -> Unit, viewModel: HomeViewModel = hiltViewModel()) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val jumpBackIn by viewModel.jumpBackIn.collectAsStateWithLifecycle()
    // "Artist • Album", or "• Single" when there is no album, as HomeFeedItem.displayItem() does.
    val subtitle = { t: Track -> "${t.artist} • ${t.album ?: "Single"}" }

    NavigationBarView(title = "Home", onProfile = onProfile) {
        item { Spacer(Modifier.height(16.dp)) }
        if (ui.isLoading && ui.topSongs.isEmpty()) item { StatusMessage("Loading Home Feed...") }
        ui.errorMessage?.let { msg -> if (ui.topSongs.isEmpty()) item { StatusMessage("Unable to Load Home\n$msg") } }

        if (jumpBackIn.isNotEmpty()) item {
            HorizontalTrackSection("Jump Back In", jumpBackIn, subtitle) { viewModel.play(it, jumpBackIn) }
            Spacer(Modifier.height(24.dp))
        }
        if (ui.topSongs.isNotEmpty()) item {
            HorizontalTrackSection("Top Songs", ui.topSongs, subtitle) { viewModel.play(it, ui.topSongs) }
            Spacer(Modifier.height(24.dp))
        }
        if (ui.trending.isNotEmpty()) item {
            HorizontalTrackSection("Trending", ui.trending, { it.artist }) { viewModel.play(it, ui.trending) }
            Spacer(Modifier.height(24.dp))
        }
    }
}
