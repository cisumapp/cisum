package aaravgupta.cisum

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.service.PlaybackStateSnapshot
import aaravgupta.cisum.ui.navigation.cisumDestination
import aaravgupta.cisum.ui.screens.discover.DiscoverScreen
import aaravgupta.cisum.ui.screens.home.HomeScreen
import aaravgupta.cisum.ui.screens.library.LibraryScreen
import aaravgupta.cisum.ui.screens.player.PlayerScreen
import aaravgupta.cisum.ui.screens.profile.ProfileScreen
import aaravgupta.cisum.ui.screens.search.SearchScreen
import aaravgupta.cisum.ui.screens.search.SearchViewModel
import aaravgupta.cisum.ui.theme.Cisum
import aaravgupta.cisum.ui.theme.IOSFont
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import kotlin.math.roundToInt

private data class TabSpec(val destination: cisumDestination, val title: String, val icon: ImageVector)

/** RootView's iOS 26 TabView: three tabs in the pill, Search as its own round button (role: .search). */
private val pillTabs = listOf(
    TabSpec(cisumDestination.Home, "Home", Icons.Filled.Home),
    TabSpec(cisumDestination.Discover, "Discover", Icons.Filled.Language),
    TabSpec(cisumDestination.Library, "Library", Icons.AutoMirrored.Filled.QueueMusic),
)

/** RootView.swift (iOS branch). */
@Composable
fun cisumApp(modifier: Modifier = Modifier, shell: ShellViewModel = hiltViewModel()) {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route ?: cisumDestination.Home.route
    val nowPlaying by shell.nowPlaying.collectAsStateWithLifecycle()
    val playback by shell.playbackState.collectAsStateWithLifecycle()
    val searchViewModel: SearchViewModel = hiltViewModel()
    var lastPillTab by rememberSaveable { mutableStateOf(cisumDestination.Home.route) }

    var isPlayerExpanded by rememberSaveable { mutableStateOf(false) }
    BackHandler(enabled = isPlayerExpanded) { isPlayerExpanded = false }
    LaunchedEffect(Unit) { shell.expandRequests.collect { isPlayerExpanded = true } }
    // Frame stats are bucketed by what is on screen.
    LaunchedEffect(route, isPlayerExpanded) { aaravgupta.cisum.perf.Perf.screen = if (isPlayerExpanded) "player" else route }
    LaunchedEffect(Unit) { aaravgupta.cisum.perf.Perf.mark("first composition") }

    // The tab content recedes behind the player like a sheet presentation.
    val overlayProgress by animateFloatAsState(
        if (isPlayerExpanded) 1f else 0f,
        spring(dampingRatio = 0.82f, stiffness = Spring.StiffnessMediumLow),
        label = "overlayProgress",
    )
    val backdrop = rememberLayerBackdrop()
    val c = Cisum.colors

    fun go(destination: cisumDestination) {
        if (destination != cisumDestination.Search && destination != cisumDestination.Profile) lastPillTab = destination.route
        nav.navigate(destination.route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    val openProfile = { go(cisumDestination.Profile) }

    Box(modifier.fillMaxSize().background(Color.Black)) {
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    val s = 1f - 0.06f * overlayProgress
                    scaleX = s; scaleY = s
                    transformOrigin = TransformOrigin(0.5f, 0f)
                }
                .clip(RoundedCornerShape((32f * overlayProgress.coerceIn(0f, 1f)).dp))
                .background(c.bg)
                .layerBackdrop(backdrop)
        ) {
            NavHost(nav, startDestination = cisumDestination.Home.route, modifier = Modifier.fillMaxSize()) {
                composable(cisumDestination.Home.route) { HomeScreen(onProfile = openProfile) }
                composable(cisumDestination.Discover.route) { DiscoverScreen(onProfile = openProfile) }
                composable(cisumDestination.Library.route) { LibraryScreen(onProfile = openProfile) }
                composable(cisumDestination.Search.route) { SearchScreen(searchViewModel) }
                composable(cisumDestination.Profile.route) { ProfileScreen() }
            }
        }

        AnimatedVisibility(
            visible = !isPlayerExpanded,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = fadeIn() + slideInVertically { it / 2 },
            exit = fadeOut() + slideOutVertically { it / 2 },
        ) {
            Column(
                Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(horizontal = 20.dp).padding(bottom = 6.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                nowPlaying?.let { track ->
                    MiniPlayer(track, playback, backdrop, shell, onExpand = { isPlayerExpanded = true })
                }
                AnimatedContent(
                    targetState = route == cisumDestination.Search.route,
                    transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.92f)) togetherWith (fadeOut() + scaleOut(targetScale = 0.92f)) },
                    label = "bottomBar",
                ) { searching ->
                    if (searching) {
                        SearchBottomBar(
                            searchViewModel, backdrop,
                            onLibrary = { go(cisumDestination.Library) },
                            onClose = { searchViewModel.clear(); go(pillTabs.first { it.destination.route == lastPillTab }.destination) },
                        )
                    } else {
                        TabBar(route, backdrop, onSelect = ::go, onSearch = { go(cisumDestination.Search) })
                    }
                }
            }
        }

        PlayerOverlay(isPlayerExpanded, backdrop) { isPlayerExpanded = false }
    }
}

/** The Liquid Glass material every floating control uses. */
@Composable
private fun Modifier.glass(backdrop: LayerBackdrop, shape: Shape, cornerPx: Float): Modifier {
    val c = Cisum.colors
    if (!aaravgupta.cisum.perf.Perf.glassEnabled) {
        return background(if (c.isDark) Color(0xFF26262C) else c.elevatedSurface.copy(alpha = 0.96f), shape)
    }
    return drawBackdrop(
        backdrop = backdrop,
        shape = { shape },
        effects = {
            vibrancy()
            blur(14.dp.toPx())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                lens(refractionHeight = 16.dp.toPx(), refractionAmount = 14.dp.toPx(), depthEffect = true)
            }
        },
        onDrawSurface = {
            drawRoundRect(
                color = if (c.isDark) Color.White.copy(alpha = 0.1f) else c.elevatedSurface.copy(alpha = 0.72f),
                cornerRadius = CornerRadius(cornerPx, cornerPx),
            )
        },
    )
}

@Composable
private fun TabBar(route: String, backdrop: LayerBackdrop, onSelect: (cisumDestination) -> Unit, onSearch: () -> Unit) {
    val c = Cisum.colors
    val barHeight = 62.dp
    val selected = pillTabs.indexOfFirst { it.destination.route == route }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        BoxWithConstraints(
            Modifier.weight(1f).height(barHeight).glass(backdrop, RoundedCornerShape(50), 400f).padding(4.dp)
        ) {
            val w = maxWidth / pillTabs.size
            val x by animateDpAsState(w * selected.coerceAtLeast(0), spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMedium), label = "tabThumb")
            if (selected >= 0) {
                Box(Modifier.offset(x = x).width(w).fillMaxHeight().background(c.primaryText.copy(alpha = 0.07f), RoundedCornerShape(50)))
            }
            Row(Modifier.fillMaxSize()) {
                pillTabs.forEachIndexed { i, tab -> TabItem(tab, i == selected) { onSelect(tab.destination) } }
            }
        }
        GlassCircle(Icons.Filled.Search, backdrop, barHeight, onSearch)
    }
}

@Composable
private fun RowScope.TabItem(tab: TabSpec, selected: Boolean, onClick: () -> Unit) {
    val c = Cisum.colors
    // iOS tints the selected tab with the accent and leaves the rest in the primary colour.
    val tint = if (selected) c.secondaryText.copy(alpha = 0.75f) else c.primaryText
    Column(
        Modifier.weight(1f).fillMaxHeight().clickable(remember { MutableInteractionSource() }, null, onClick = onClick),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(tab.icon, tab.title, tint = tint, modifier = Modifier.size(26.dp))
        Text(tab.title, color = tint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun GlassCircle(icon: ImageVector, backdrop: LayerBackdrop, size: Dp, onClick: () -> Unit) {
    Box(
        Modifier.size(size).glass(backdrop, CircleShape, 400f).clip(CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = Cisum.colors.primaryText, modifier = Modifier.size(28.dp))
    }
}

/** The Search tab's bottom accessory: library shortcut, the search field, close. */
@Composable
private fun SearchBottomBar(vm: SearchViewModel, backdrop: LayerBackdrop, onLibrary: () -> Unit, onClose: () -> Unit) {
    val c = Cisum.colors
    val query by vm.query.collectAsStateWithLifecycle()
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) { focus.requestFocus() }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        GlassCircle(Icons.AutoMirrored.Filled.QueueMusic, backdrop, 56.dp, onLibrary)
        Row(
            Modifier.weight(1f).height(56.dp).glass(backdrop, RoundedCornerShape(50), 400f).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Search, null, tint = c.secondaryText, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text("Artists, Songs, Playlists", style = IOSFont.body, color = c.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicTextField(
                    value = query,
                    onValueChange = vm::onQueryChange,
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 19.sp, color = c.primaryText),
                    cursorBrush = SolidColor(c.yellow),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { vm.submit(); keyboard?.hide() }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            if (query.isNotEmpty()) {
                Icon(Icons.Filled.Cancel, null, tint = c.secondaryText, modifier = Modifier.size(22.dp).clickable { vm.clear() })
            }
        }
        GlassCircle(Icons.Filled.Close, backdrop, 56.dp, onClose)
    }
}

/** MiniPlayer: the title over two lines and rewind / play / fast-forward, in glass. */
@Composable
private fun MiniPlayer(track: Track, playback: PlaybackStateSnapshot, backdrop: LayerBackdrop, controller: ShellViewModel, onExpand: () -> Unit) {
    val c = Cisum.colors
    Row(
        Modifier
            .fillMaxWidth()
            .height(60.dp)
            .glass(backdrop, RoundedCornerShape(50), 400f)
            .clip(RoundedCornerShape(50))
            .clickable(onClick = onExpand)
            .padding(start = 22.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            track.title,
            fontSize = 19.sp,
            lineHeight = 21.sp,
            fontWeight = FontWeight.SemiBold,
            color = c.primaryText,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        MiniButton(Icons.Filled.FastRewind) { controller.skipToPrevious() }
        MiniButton(if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow) { controller.togglePlayPause() }
        MiniButton(Icons.Filled.FastForward) { controller.skipToNext() }
    }
}

@Composable
private fun MiniButton(icon: ImageVector, onClick: () -> Unit) {
    Box(Modifier.size(46.dp).clip(CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Cisum.colors.primaryText, modifier = Modifier.size(34.dp))
    }
}

/** The expanded player, dragged down to dismiss. */
@Composable
private fun PlayerOverlay(isExpanded: Boolean, backdrop: LayerBackdrop, onDismiss: () -> Unit) {
    var drag by remember { mutableFloatStateOf(0f) }
    var height by remember { mutableFloatStateOf(1f) }
    val animatedDrag by animateFloatAsState(drag, spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow), label = "drag")

    AnimatedVisibility(
        visible = isExpanded,
        enter = slideInVertically(spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)) { it },
        exit = slideOutVertically(spring(dampingRatio = 0.9f, stiffness = Spring.StiffnessMediumLow)) { it },
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .onSizeChanged { height = it.height.toFloat().coerceAtLeast(1f) }
                .offset { IntOffset(0, animatedDrag.roundToInt()) }
                .clip(RoundedCornerShape(topStart = 34.dp, topEnd = 34.dp))
                .pointerInput(Unit) {
                    detectVerticalDragGestures(
                        onVerticalDrag = { _, d -> drag = (drag + d).coerceAtLeast(0f) },
                        onDragEnd = { val dismiss = drag > height * 0.22f; drag = 0f; if (dismiss) onDismiss() },
                        onDragCancel = { drag = 0f },
                    )
                }
        ) {
            PlayerScreen(onDismiss = onDismiss)
        }
    }
}

