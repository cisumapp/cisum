package aaravgupta.cisum.ui.components

import aaravgupta.cisum.R
import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.ui.theme.Cisum
import aaravgupta.cisum.ui.theme.IOSFont
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

/** ResponsiveLayout.scaleFactor: layout is drawn for a 390pt-wide phone and scaled to the screen. */
@Composable
fun layoutScale(): Float = LocalConfiguration.current.screenWidthDp / 390f

/** Kingfisher's ArtworkImage: the artwork, or the surface colour while it loads. */
@Composable
fun ArtworkImage(url: String?, modifier: Modifier = Modifier, shape: Shape = RoundedCornerShape(0.dp)) {
    Box(modifier.clip(shape).background(Cisum.colors.surface)) {
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

/** ProfileButton: the round avatar at the top right of every tab's large title. */
@Composable
fun ProfileButton(imageUrl: String?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = Cisum.colors
    Box(
        modifier
            .size(54.dp)
            .shadow(10.dp, CircleShape, ambientColor = Color.Black.copy(0.25f), spotColor = Color.Black.copy(0.25f))
            .background(c.elevatedSurface, CircleShape)
            .border(3.dp, Color.White.copy(alpha = if (c.isDark) 0.18f else 0.7f), CircleShape)
            .padding(4.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (imageUrl != null) {
            AsyncImage(imageUrl, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Icon(Icons.Filled.Person, null, tint = c.secondaryText, modifier = Modifier.size(28.dp))
        }
    }
}

/**
 * NavigationBarView: a large bold title with the profile button, over scrolling content that fades
 * out under it. The title shrinks 35 → 30 over the first 60pt of scroll, like iOS.
 */
@Composable
fun NavigationBarView(
    title: String,
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    profileImageUrl: String? = null,
    onProfile: () -> Unit = {},
    bottomPadding: Dp = 160.dp,
    content: LazyListScope.() -> Unit,
) {
    val c = Cisum.colors
    val density = LocalDensity.current
    val progress by remember {
        derivedStateOf {
            if (state.firstVisibleItemIndex > 0) 1f
            else with(density) { (state.firstVisibleItemScrollOffset.toDp() / 60.dp).coerceIn(0f, 1f) }
        }
    }
    Box(modifier.fillMaxSize().background(c.bg)) {
        LazyColumn(state = state, contentPadding = PaddingValues(bottom = bottomPadding), modifier = Modifier.fillMaxSize()) {
            item { Spacer(Modifier.statusBarsPadding().height(110.dp)) }
            content()
        }
        // Variable blur stand-in: the background fades in behind the title as content scrolls under it.
        Box(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(96.dp)
                .graphicsLayer { alpha = progress }
                .background(Brush.verticalGradient(listOf(c.bg, c.bg.copy(alpha = 0.92f), c.bg.copy(alpha = 0f))))
        )
        Box(Modifier.fillMaxWidth().background(c.bg.copy(alpha = progress)).statusBarsPadding())
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = 16.dp, end = 16.dp, top = 22.dp - 12.dp * progress),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                fontSize = (35f - 5f * progress).sp,
                fontWeight = FontWeight.Bold,
                color = c.primaryText,
                modifier = Modifier.weight(1f),
            )
            ProfileButton(profileImageUrl, onProfile, Modifier.graphicsLayer { scaleX = 0.9f - 0.043f * progress; scaleY = scaleX })
        }
    }
}

/** TrackCard: square artwork with a vinyl record peeking out behind it, title, artist, duration. */
@Composable
fun TrackCard(
    trackName: String,
    artistName: String,
    artworkUrl: String?,
    duration: String = "",
    onClick: () -> Unit,
) {
    val s = layoutScale()
    val side = (140 * s).dp
    Box(
        Modifier
            .width((160 * s).dp + (16 * s).dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding((8 * s).dp)
    ) {
        // The record, rotated 180° and pinned top-trailing so it slides out from under the sleeve.
        Box(Modifier.align(Alignment.TopEnd).size(side).rotate(180f)) {
            // Black masked by the grooves, then the grooves over it: a dark record, as on iOS.
            Image(painterResource(R.drawable.vinyl_grooves), null, Modifier.fillMaxSize(), colorFilter = ColorFilter.tint(Color.Black, BlendMode.SrcIn))
            Image(painterResource(R.drawable.vinyl_grooves), null, Modifier.fillMaxSize())
            Image(painterResource(R.drawable.vinyl_overlay), null, Modifier.fillMaxSize())
            Image(painterResource(R.drawable.vinyl_center), null, Modifier.fillMaxSize())
        }
        Column(Modifier.width((160 * s).dp)) {
            ArtworkImage(
                artworkUrl,
                Modifier
                    .size(side)
                    .shadow(5.dp, RoundedCornerShape(0.dp), clip = false)
            )
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Column(Modifier.weight(1f)) {
                    Text(trackName, style = IOSFont.caption, fontWeight = FontWeight.SemiBold, color = Cisum.colors.primaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(artistName, fontSize = (10 * s).sp, fontWeight = FontWeight.SemiBold, color = Cisum.colors.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (duration.isNotEmpty()) {
                    Text(duration, fontSize = (10 * s).sp, fontWeight = FontWeight.SemiBold, color = Cisum.colors.secondaryText, modifier = Modifier.padding(end = (25 * s).dp))
                }
            }
        }
    }
}

/** HomeView's HorizontalTrackSection: a title2-bold header over a row of TrackCards. */
@Composable
fun HorizontalTrackSection(title: String, tracks: List<Track>, subtitle: (Track) -> String, onPlay: (Track) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = IOSFont.title2, fontWeight = FontWeight.Bold, color = Cisum.colors.primaryText, modifier = Modifier.padding(horizontal = 16.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(tracks, key = { it.id }) { t ->
                TrackCard(t.title, subtitle(t), t.artworkUrl, onClick = { onPlay(t) })
            }
        }
    }
}

/** TrackListItem: 60pt rounded artwork, title, (E) artist, duration and an ellipsis. */
@Composable
fun TrackListItem(
    trackName: String,
    artistName: String,
    artworkUrl: String?,
    modifier: Modifier = Modifier,
    duration: String = "",
    isExplicit: Boolean = false,
    artworkShape: Shape = RoundedCornerShape(8.dp),
    onMore: () -> Unit = {},
) {
    val s = layoutScale()
    val c = Cisum.colors
    Row(
        modifier.fillMaxWidth().height((70 * s).dp + (16 * s).dp).padding((8 * s).dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ArtworkImage(artworkUrl, Modifier.size((60 * s).dp), artworkShape)
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(trackName, style = IOSFont.subheadline, fontWeight = FontWeight.SemiBold, color = c.primaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isExplicit) {
                    Box(Modifier.size((11 * s).dp).background(c.secondaryText, RoundedCornerShape(2.dp)), contentAlignment = Alignment.Center) {
                        Text("E", fontSize = (8 * s).sp, fontWeight = FontWeight.Bold, color = c.bg)
                    }
                    Spacer(Modifier.width(4.dp))
                }
                Text(artistName, style = IOSFont.caption2, fontWeight = FontWeight.SemiBold, color = c.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(Modifier.padding(end = (10 * s).dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy((10 * s).dp)) {
            if (duration.isNotEmpty()) Text(duration, style = IOSFont.caption, fontWeight = FontWeight.SemiBold, color = c.secondaryText)
            Icon(Icons.Filled.MoreHoriz, null, tint = c.secondaryText, modifier = Modifier.size(26.dp).clickable(onClick = onMore))
        }
    }
}

fun formatDuration(ms: Long): String {
    if (ms <= 0) return ""
    val total = ms / 1000
    return "%d:%02d".format(total / 60, total % 60)
}

/** A simple centred loading / empty message, like ProgressView and ContentUnavailableView. */
@Composable
fun StatusMessage(text: String) {
    Text(
        text,
        style = IOSFont.subheadline,
        color = Cisum.colors.secondaryText,
        modifier = Modifier.fillMaxWidth().padding(24.dp),
    )
}

