package aaravgupta.cisum.ui.screens.player

import aaravgupta.cisum.R
import aaravgupta.cisum.data.model.Track
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Airplay
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlinx.coroutines.isActive

@Composable
fun NowPlayingView(
    uiState: PlayerUiState,
    positionMs: () -> Long,
    onDismiss: () -> Unit,
    onTogglePlayback: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
    onSeek: (Long) -> Unit,
    onVolumeChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    val nowPlaying = uiState.nowPlaying
    val accentColor = MaterialTheme.colorScheme.primary

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFF101010))
    ) {
        PlayerBackground(
            artworkUrl = nowPlaying?.artworkUrl,
            isPlaying = uiState.isPlaying,
            accentColor = accentColor
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            PlayerHeader(
                onDismiss = onDismiss
            )

            ArtworkSpacer()

            if (nowPlaying == null) {
                EmptyNowPlayingContent(
                    uiState = uiState
                )
                return@Column
            }

            SongInfoSection(
                nowPlaying = nowPlaying,
                uiState = uiState
            )

            PlayerControlsSection(
                positionMs = positionMs,
                uiState = uiState,
                onTogglePlayback = onTogglePlayback,
                onSkipPrevious = onSkipPrevious,
                onSkipNext = onSkipNext,
                onSeek = onSeek,
                onVolumeChange = onVolumeChange,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun PlayerHeader(
    onDismiss: () -> Unit
) {
    // iOS shows neither a grabber nor a chevron; the whole player drags down to dismiss.
    Spacer(Modifier.fillMaxWidth().height(15.dp))
}

@Composable
private fun ArtworkSpacer() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 15.dp)
            .aspectRatio(1f)
    )
}

@Composable
private fun SongInfoSection(
    nowPlaying: Track,
    uiState: PlayerUiState
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 80.dp, start = 15.dp, end = 15.dp)
            .height(80.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = nowPlaying.title,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 26.sp,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold
                )

                if (uiState.isExplicit) {
                    Text(
                        text = "E",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White.copy(alpha = 0.86f),
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color.White.copy(alpha = 0.2f))
                            .padding(horizontal = 4.dp, vertical = 2.dp)
                    )
                }
            }

            Text(
                text = nowPlaying.artist,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontSize = 22.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.82f)
            )

            // "YouTube Music · audio/mp4 · mp4a.40.2", as one quiet line.
            Text(
                text = listOf(uiState.streamingServiceName, uiState.audioQualityLabel, uiState.audioCodecLabel)
                    .filter { it.isNotBlank() }.joinToString(" · "),
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.6f),
                maxLines = 1
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = {}) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = stringResource(id = R.string.player_favorite),
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }

            IconButton(onClick = {}) {
                Icon(
                    imageVector = Icons.Default.MoreHoriz,
                    contentDescription = stringResource(id = R.string.player_more_actions),
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
        }
    }
}

@Composable
private fun InfoBadge(
    title: String,
    icon: @Composable () -> Unit
) {
    Surface(
        color = Color.White.copy(alpha = 0.2f),
        shape = RoundedCornerShape(percent = 50)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            icon()
            Text(
                text = title,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun PlayerControlsSection(
    positionMs: () -> Long,
    uiState: PlayerUiState,
    onTogglePlayback: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
    onSeek: (Long) -> Unit,
    onVolumeChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 15.dp)
    ) {
        val controlSpacing = maxWidth * 0.18f

        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            MusicProgressScrubber(
                currentTimeMs = positionMs,
                durationMs = uiState.playbackDurationMs,
                onSeek = onSeek,
                modifier = Modifier.height(72.dp)
            )

            Spacer(modifier = Modifier.weight(1f))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(
                    space = controlSpacing,
                    alignment = Alignment.CenterHorizontally
                ),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = onSkipPrevious,
                    enabled = uiState.canSkipPrevious
                ) {
                    Icon(
                        imageVector = Icons.Default.FastRewind,
                        contentDescription = stringResource(id = R.string.player_previous),
                        tint = Color.White,
                        modifier = Modifier.size(48.dp)
                    )
                }

                Box(
                    modifier = Modifier
                        .size(74.dp)
                        .clip(CircleShape)
                        .clickable(
                            enabled = uiState.nowPlaying != null,
                            onClick = onTogglePlayback
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (uiState.isPlaying) {
                            Icons.Default.Pause
                        } else {
                            Icons.Default.PlayArrow
                        },
                        contentDescription = stringResource(id = R.string.player_toggle_playback),
                        tint = Color.White,
                        modifier = Modifier.size(64.dp)
                    )
                }

                IconButton(
                    onClick = onSkipNext,
                    enabled = uiState.canSkipNext
                ) {
                    Icon(
                        imageVector = Icons.Default.FastForward,
                        contentDescription = stringResource(id = R.string.player_next),
                        tint = Color.White,
                        modifier = Modifier.size(48.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            VolumeSlider(
                volume = uiState.volume,
                onVolumeChange = onVolumeChange,
                modifier = Modifier.height(30.dp)
            )

            Spacer(modifier = Modifier.weight(1f))

            FooterControls(
                spacing = controlSpacing
            )
        }
    }
}

@Composable
private fun MusicProgressScrubber(
    currentTimeMs: () -> Long,
    durationMs: Long,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val currentTimeMs = currentTimeMs() // read here: position changes recompose only the scrubber
    val safeDuration = durationMs.coerceAtLeast(0L)
    val clampedProgress = if (safeDuration > 0L) {
        (currentTimeMs.toFloat() / safeDuration.toFloat()).coerceIn(0f, 1f)
    } else {
        0f
    }

    var isDragging by remember { mutableStateOf(false) }
    var sliderProgress by remember { mutableFloatStateOf(clampedProgress) }

    LaunchedEffect(clampedProgress, isDragging) {
        if (!isDragging) {
            sliderProgress = clampedProgress
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.Center
    ) {
        Slider(
            value = sliderProgress,
            onValueChange = { value ->
                isDragging = true
                sliderProgress = value
            },
            onValueChangeFinished = {
                val targetPosition = (sliderProgress * safeDuration.toFloat()).roundToLong()
                onSeek(targetPosition)
                isDragging = false
            },
            enabled = safeDuration > 0L,
            valueRange = 0f..1f,
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.White,
                inactiveTrackColor = Color.White.copy(alpha = 0.35f)
            ),
            modifier = Modifier.fillMaxWidth()
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = formatTime(currentTimeMs),
                style = MaterialTheme.typography.labelMedium,
                color = Color.White.copy(alpha = 0.82f)
            )
            Text(
                text = formatTime(safeDuration),
                style = MaterialTheme.typography.labelMedium,
                color = Color.White.copy(alpha = 0.82f)
            )
        }
    }
}

@Composable
private fun VolumeSlider(
    volume: Float,
    onVolumeChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = Icons.Default.VolumeDown,
            contentDescription = stringResource(id = R.string.player_volume),
            tint = Color.White,
            modifier = Modifier.size(18.dp)
        )

        Slider(
            value = volume,
            onValueChange = { newVolume ->
                onVolumeChange(newVolume.coerceIn(0f, 1f))
            },
            valueRange = 0f..1f,
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.White,
                inactiveTrackColor = Color.White.copy(alpha = 0.35f)
            ),
            modifier = Modifier.weight(1f)
        )

        Icon(
            imageVector = Icons.Default.VolumeUp,
            contentDescription = stringResource(id = R.string.player_volume),
            tint = Color.White,
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
private fun FooterControls(
    spacing: Dp
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(
            space = spacing,
            alignment = Alignment.CenterHorizontally
        ),
        verticalAlignment = Alignment.Top
    ) {
        IconButton(onClick = {}) {
            Icon(
                imageVector = Icons.Default.FormatQuote,
                contentDescription = stringResource(id = R.string.player_lyrics),
                tint = Color.White,
                modifier = Modifier.size(30.dp)
            )
        }

        Box(
            modifier = Modifier
                .size(48.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Airplay,
                contentDescription = stringResource(id = R.string.player_airplay),
                tint = Color.White,
                modifier = Modifier.size(26.dp)
            )
        }

        IconButton(onClick = {}) {
            Icon(
                imageVector = Icons.Default.QueueMusic,
                contentDescription = stringResource(id = R.string.player_queue),
                tint = Color.White,
                modifier = Modifier.size(30.dp)
            )
        }
    }
}

@Composable
private fun EmptyNowPlayingContent(
    uiState: PlayerUiState
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 15.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(id = R.string.player_empty),
            style = MaterialTheme.typography.titleMedium,
            color = Color.White
        )

        Text(
            text = stringResource(
                id = if (uiState.isConnected) {
                    R.string.player_status_connected
                } else {
                    R.string.player_status_connecting
                }
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.82f)
        )

        val playbackError = uiState.playbackError
        if (!playbackError.isNullOrBlank()) {
            Text(
                text = playbackError,
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.82f)
            )
        }
    }
}

@Composable
private fun PlayerBackground(
    artworkUrl: String?,
    isPlaying: Boolean,
    accentColor: Color
) {
    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            accentColor.copy(alpha = 0.85f),
                            accentColor.copy(alpha = 0.55f),
                            Color(0xFF101010)
                        )
                    )
                )
        )

        VinylStage(
            artworkUrl = artworkUrl,
            isPlaying = isPlaying,
            accentColor = accentColor,
            modifier = Modifier.fillMaxSize()
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White.copy(alpha = 0.1f))
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.35f))
        )
    }
}

@Composable
private fun VinylStage(
    artworkUrl: String?,
    isPlaying: Boolean,
    accentColor: Color,
    modifier: Modifier = Modifier
) {
    // Read in the draw phase only: the spin redraws one layer, it does not recompose the stage.
    val rotationDegrees = rememberVinylRotation(
        isPlaying = isPlaying
    )

    BoxWithConstraints(
        modifier = modifier
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 35.dp),
            verticalAlignment = Alignment.Top
        ) {
            VinylStaticDisk(
                modifier = Modifier.offset(x = (-60).dp)
            )

            Spacer(modifier = Modifier.weight(1f))

            VinylStaticDisk(
                modifier = Modifier.offset(x = 55.dp)
            )
        }

        val screenAspectRatio = maxHeight.value / maxWidth.value
        val referenceAspectRatio = 19.5f / 9f
        val normalizedAspect = (screenAspectRatio / referenceAspectRatio).coerceIn(0.9f, 1.2f)

        // Keep the hero vinyl oversized and square; let it extend offscreen on purpose.
        val heroSizeScale = (1.28f + ((normalizedAspect - 1f) * 0.18f)).coerceIn(1.22f, 1.38f)
        val heroSize = maxHeight * heroSizeScale

        val heroRatio = (0.83f - ((normalizedAspect - 1f) * 0.06f)).coerceIn(0.74f, 0.86f)
        val heroTopOffset = (maxHeight * heroRatio) - (heroSize / 2.275f)

        Box(
            modifier = Modifier
                .requiredSize(heroSize)
                .align(Alignment.TopCenter)
                .offset(y = heroTopOffset)
        ) {
            VinylDisk(
                size = heroSize,
                rotationDegrees = rotationDegrees,
                artworkUrl = artworkUrl
            )

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(CircleShape)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.Transparent,
                                accentColor.copy(alpha = 0.42f),
                                accentColor.copy(alpha = 0.68f),
                                accentColor.copy(alpha = 0.92f),
                                Color.Black
                            )
                        )
                    )
            )
        }
    }
}

@Composable
private fun VinylStaticDisk(
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier) {
        VinylDisk(
            size = 200.dp,
            rotationDegrees = { 0f },
            artworkUrl = null
        )
    }
}

@Composable
private fun VinylDisk(
    size: Dp,
    rotationDegrees: () -> Float,
    artworkUrl: String?
) {
    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    rotationZ = rotationDegrees()
                },
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(1.dp)
                    .clip(CircleShape)
            ) {
                if (artworkUrl.isNullOrBlank()) {
                    Image(
                        painter = painterResource(id = R.drawable.not_playing),
                        contentDescription = stringResource(id = R.string.player_artwork),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    AsyncImage(
                        // The hero record is ~1.3x screen height; decoding the cover at that size
                        // is a ~36 MB bitmap rotated every frame. 1024 px is sharp at this scale.
                        model = coil.request.ImageRequest.Builder(androidx.compose.ui.platform.LocalContext.current)
                            .data(artworkUrl).size(1024).build(),
                        contentDescription = stringResource(id = R.string.player_artwork),
                        placeholder = painterResource(id = R.drawable.not_playing),
                        error = painterResource(id = R.drawable.not_playing),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }

            Image(
                painter = painterResource(id = R.drawable.vinyl_grooves),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(5.dp),
                alpha = 0.5f
            )

            Image(
                painter = painterResource(id = R.drawable.vinyl_overlay),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        Image(
            painter = painterResource(id = R.drawable.vinyl_center),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
    }
}

@Composable
private fun rememberVinylRotation(
    isPlaying: Boolean
): () -> Float {
    val rotation = remember { Animatable(0f) }
    val oneFullTurnDurationMs = ((360f / 35f) * 1_000f).roundToInt()

    LaunchedEffect(isPlaying) {
        if (!isPlaying) {
            return@LaunchedEffect
        }

        while (isActive) {
            rotation.animateTo(
                targetValue = rotation.value + 360f,
                animationSpec = tween(
                    durationMillis = oneFullTurnDurationMs,
                    easing = LinearEasing
                )
            )
            rotation.snapTo(rotation.value % 360f)
        }
    }

    return { rotation.value }
}

private fun formatTime(milliseconds: Long): String {
    val safeMillis = milliseconds.coerceAtLeast(0L)
    val totalSeconds = safeMillis / 1_000L
    val minutes = totalSeconds / 60L
    val seconds = totalSeconds % 60L
    return String.format("%d:%02d", minutes, seconds)
}
