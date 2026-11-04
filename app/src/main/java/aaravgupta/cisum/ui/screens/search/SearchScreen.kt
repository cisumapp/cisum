package aaravgupta.cisum.ui.screens.search

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.remote.swift.MusicArtist
import aaravgupta.cisum.data.remote.swift.MusicPlaylist
import aaravgupta.cisum.ui.components.ArtworkImage
import aaravgupta.cisum.ui.components.StatusMessage
import aaravgupta.cisum.ui.components.TrackListItem
import aaravgupta.cisum.ui.components.formatDuration
import aaravgupta.cisum.ui.theme.Cisum
import aaravgupta.cisum.ui.theme.IOSFont
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

private enum class SearchFilter(val label: String) { All("All Results"), Artists("Artists"), Songs("Songs"), Playlists("Playlists") }

/** SearchView.swift + SearchResultsList.swift. The search field lives in the shell's bottom bar. */
@Composable
fun SearchScreen(viewModel: SearchViewModel) {
    val c = Cisum.colors
    val state by viewModel.state.collectAsStateWithLifecycle()
    val recent by viewModel.recentSearches.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val suggestions by viewModel.suggestions.collectAsStateWithLifecycle()

    Box(Modifier.fillMaxSize().background(c.bg).statusBarsPadding()) {
        when (val s = state) {
            SearchViewModel.State.Idle ->
                if (recent.isEmpty()) {
                    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Icon(Icons.Filled.Search, null, tint = c.secondaryText, modifier = Modifier.size(44.dp))
                        Spacer(Modifier.height(10.dp))
                        Text("Search for something", style = IOSFont.title3, fontWeight = FontWeight.Bold, color = c.primaryText)
                    }
                } else {
                    LazyColumn(contentPadding = PaddingValues(top = 16.dp, bottom = 160.dp)) {
                        item { Text("Recent Searches", style = IOSFont.footnote, fontWeight = FontWeight.SemiBold, color = c.secondaryText, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
                        items(recent) { r ->
                            Row(Modifier.fillMaxWidth().clickable { viewModel.submit(r) }.padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.History, null, tint = c.yellow, modifier = Modifier.size(20.dp))
                                Spacer(Modifier.width(12.dp))
                                Text(r, style = IOSFont.body, color = c.primaryText)
                            }
                        }
                    }
                }
            SearchViewModel.State.Loading -> Column(Modifier.padding(horizontal = 20.dp).padding(top = 72.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                Box(Modifier.fillMaxWidth().aspectRatio(7f / 6f).background(c.surface, RoundedCornerShape(24.dp)))
                repeat(4) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(60.dp).background(c.surface, RoundedCornerShape(8.dp)))
                        Spacer(Modifier.width(12.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.width(150.dp).height(12.dp).background(c.surface, RoundedCornerShape(4.dp)))
                            Box(Modifier.width(90.dp).height(10.dp).background(c.surface, RoundedCornerShape(4.dp)))
                        }
                    }
                }
            }
            is SearchViewModel.State.Error -> StatusMessage("Error\n${s.message}")
            is SearchViewModel.State.Success -> Results(s, query, viewModel::play)
        }

        // Suggestions, newest at the bottom right above the search field, as on iOS.
        if (query.isNotEmpty() && suggestions.isNotEmpty() && state !is SearchViewModel.State.Success) {
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(c.bg).padding(bottom = 150.dp)) {
                suggestions.take(8).reversed().forEach { sug ->
                    Row(Modifier.fillMaxWidth().clickable { viewModel.submit(sug) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Search, null, tint = c.yellow, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(sug, style = IOSFont.body, color = c.primaryText)
                    }
                    Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.primaryText.copy(alpha = 0.1f)))
                }
            }
        }
    }
}

@Composable
private fun Results(s: SearchViewModel.State.Success, query: String, play: (Track) -> Unit) {
    var filter by remember(query) { mutableStateOf(SearchFilter.All) }
    val available = SearchFilter.entries.filter {
        when (it) {
            SearchFilter.All -> true
            SearchFilter.Artists -> s.artists.isNotEmpty()
            SearchFilter.Songs -> s.songs.isNotEmpty()
            SearchFilter.Playlists -> s.playlists.isNotEmpty()
        }
    }
    val topArtist = s.artists.firstOrNull()?.takeIf { a -> a.name.lowercase().split(" ").all { it in query.lowercase() } || query.lowercase().contains(a.name.lowercase()) }

    Column(Modifier.fillMaxSize()) {
        SegmentedPicker(available, filter) { filter = it }
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 160.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
            when (filter) {
                SearchFilter.All -> {
                    val cardSongs = (topArtist?.let { a -> s.songs.filter { it.artist.contains(a.name, ignoreCase = true) } } ?: s.songs).take(4)
                    if (topArtist != null) {
                        item { TopArtistCard(topArtist, cardSongs.mapNotNull { it.artworkUrl }) }
                        items(cardSongs, key = { "top-${it.id}" }) { SongRow(it, play) }
                        item { Spacer(Modifier.height(32.dp)) }
                    }
                    if (s.artists.isNotEmpty()) {
                        item { SectionHeader("Artists") { filter = SearchFilter.Artists } }
                        item {
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(26.dp)) { items(s.artists, key = { it.id }) { ArtistBubble(it) } }
                            Spacer(Modifier.height(32.dp))
                        }
                    }
                    val preview = s.songs.filterNot { t -> topArtist != null && cardSongs.any { it.id == t.id } }.take(4)
                    if (preview.isNotEmpty()) {
                        item { SectionHeader("Songs") { filter = SearchFilter.Songs } }
                        items(preview, key = { "p-${it.id}" }) { SongRow(it, play) }
                        item { Spacer(Modifier.height(32.dp)) }
                    }
                    if (s.playlists.isNotEmpty()) {
                        item { SectionHeader("Playlists") { filter = SearchFilter.Playlists } }
                        item { LazyRow(horizontalArrangement = Arrangement.spacedBy(26.dp)) { items(s.playlists, key = { it.id }) { PlaylistCard(it) } } }
                    }
                }
                SearchFilter.Artists -> items(s.artists, key = { it.id }) { ArtistRow(it) }
                SearchFilter.Songs -> items(s.songs, key = { it.id }) { SongRow(it, play) }
                SearchFilter.Playlists -> items(s.playlists, key = { it.id }) { PlaylistRow(it) }
            }
        }
    }
}

/** `.pickerStyle(.segmented)`: a rounded track with a sliding white thumb. */
@Composable
private fun SegmentedPicker(options: List<SearchFilter>, selected: SearchFilter, onSelect: (SearchFilter) -> Unit) {
    val c = Cisum.colors
    BoxWithConstraints(
        Modifier.padding(horizontal = 20.dp, vertical = 8.dp).fillMaxWidth().height(36.dp)
            .background(c.surface, RoundedCornerShape(50)).padding(3.dp)
    ) {
        val w = maxWidth / options.size
        val x by animateDpAsState(w * options.indexOf(selected).coerceAtLeast(0), spring(dampingRatio = 0.8f, stiffness = 500f), label = "segment")
        Box(Modifier.offset(x = x).width(w).fillMaxHeight().shadow(2.dp, RoundedCornerShape(50)).background(if (c.isDark) c.elevatedSurface else Color.White, RoundedCornerShape(50)))
        Row(Modifier.fillMaxSize()) {
            options.forEach { o ->
                Box(Modifier.weight(1f).fillMaxHeight().clickable { onSelect(o) }, contentAlignment = Alignment.Center) {
                    Text(o.label, style = IOSFont.subheadline, fontWeight = if (o == selected) FontWeight.SemiBold else FontWeight.Normal, color = c.primaryText, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String, onClick: () -> Unit) {
    Row(Modifier.clickable(onClick = onClick).padding(bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IOSFont.title3, fontWeight = FontWeight.Bold, color = Cisum.colors.primaryText)
        Spacer(Modifier.width(4.dp))
        Icon(Icons.Filled.ChevronRight, null, tint = Cisum.colors.secondaryText, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun SongRow(t: Track, play: (Track) -> Unit) {
    TrackListItem(
        t.title,
        listOfNotNull(t.artist.ifEmpty { null }, t.album).joinToString(" • "),
        t.artworkUrl,
        Modifier.clickable { play(t) },
        duration = formatDuration(t.durationMs),
        isExplicit = t.isExplicit,
    )
}

/** TopArtistSearchResultCard: the named artist's photo, big, with their top songs' covers. */
@Composable
private fun TopArtistCard(artist: MusicArtist, previews: List<String>) {
    Box(Modifier.fillMaxWidth().aspectRatio(7f / 6f).shadow(8.dp, RoundedCornerShape(24.dp)).background(Cisum.colors.surface, RoundedCornerShape(24.dp))) {
        ArtworkImage(artist.thumbnailUrl?.replace(Regex("=w\\d+-h\\d+"), "=w800-h800"), Modifier.fillMaxSize(), RoundedCornerShape(24.dp))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.65f)), RoundedCornerShape(24.dp)))
        Column(Modifier.align(Alignment.BottomStart).padding(18.dp)) {
            Text(artist.name, style = IOSFont.title, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
            artist.subtitle?.let { Text(it, style = IOSFont.footnote, color = Color.White.copy(alpha = 0.8f)) }
            if (previews.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    previews.take(4).forEach { ArtworkImage(it, Modifier.size(44.dp), RoundedCornerShape(8.dp)) }
                }
            }
        }
    }
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun ArtistBubble(a: MusicArtist) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        ArtworkImage(a.thumbnailUrl, Modifier.size(100.dp), CircleShape)
        Text(a.name, style = IOSFont.footnote, fontWeight = FontWeight.Medium, color = Cisum.colors.primaryText.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(100.dp))
    }
}

@Composable
private fun ArtistRow(a: MusicArtist) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        ArtworkImage(a.thumbnailUrl, Modifier.size(60.dp), CircleShape)
        Spacer(Modifier.width(12.dp))
        Column {
            Text(a.name, style = IOSFont.subheadline, fontWeight = FontWeight.SemiBold, color = Cisum.colors.primaryText)
            a.subtitle?.let { Text(it, style = IOSFont.caption2, fontWeight = FontWeight.SemiBold, color = Cisum.colors.secondaryText) }
        }
    }
}

@Composable
private fun PlaylistCard(p: MusicPlaylist) {
    Column(Modifier.width(160.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ArtworkImage(p.thumbnailUrl, Modifier.size(160.dp), RoundedCornerShape(12.dp))
        Text(p.title, style = IOSFont.footnote, fontWeight = FontWeight.SemiBold, color = Cisum.colors.primaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        p.author?.let { Text(it, style = IOSFont.caption, color = Cisum.colors.secondaryText, maxLines = 1) }
    }
}

@Composable
private fun PlaylistRow(p: MusicPlaylist) {
    TrackListItem(p.title, p.author ?: "Playlist", p.thumbnailUrl)
}
