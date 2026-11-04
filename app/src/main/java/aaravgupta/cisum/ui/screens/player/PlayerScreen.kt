package aaravgupta.cisum.ui.screens.player

import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.navigation.compose.hiltViewModel

@Composable
fun PlayerScreen(
    onDismiss: () -> Unit,
    viewModel: PlayerViewModel = hiltViewModel()
) {
    val uiState = viewModel.uiState.collectAsStateWithLifecycle().value
    val position = viewModel.positionMs.collectAsStateWithLifecycle()

    NowPlayingView(
        uiState = uiState,
        positionMs = { position.value },
        onDismiss = onDismiss,
        onTogglePlayback = viewModel::togglePlayback,
        onSkipPrevious = viewModel::skipToPrevious,
        onSkipNext = viewModel::skipToNext,
        onSeek = viewModel::seekTo,
        onVolumeChange = viewModel::setVolume
    )
}
