package aaravgupta.cisum.ui.screens.library

import aaravgupta.cisum.ui.components.NavigationBarView
import aaravgupta.cisum.ui.theme.Cisum
import aaravgupta.cisum.ui.theme.IOSFont
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** One front-page row: title, SF-symbol stand-in, count. */
data class LibraryCategory(val title: String, val icon: ImageVector, val count: Int)

/**
 * LibraryView.swift. Rows appear only for kinds the library has, as on iOS; with nothing imported it
 * shows the same empty state.
 * ponytail: no playlist store on Android yet (iOS fills it from Spotify / YouTube / Apple Music
 * imports), so categories is empty until the import flows are ported.
 */
@Composable
fun LibraryScreen(onProfile: () -> Unit, categories: List<LibraryCategory> = emptyList()) {
    NavigationBarView(title = "Library", onProfile = onProfile) {
        if (categories.isEmpty()) {
            item { EmptyLibrary() }
        } else {
            item {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    categories.forEach { LibraryCategoryRow(it) }
                }
            }
        }
    }
}

@Composable
private fun LibraryCategoryRow(category: LibraryCategory) {
    val c = Cisum.colors
    Column(Modifier.clickable { }) {
        Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(category.icon, null, tint = c.yellow, modifier = Modifier.width(28.dp).size(26.dp))
            Spacer(Modifier.width(14.dp))
            Text(category.title, style = IOSFont.title3, color = c.primaryText, modifier = Modifier.weight(1f))
            Text("${category.count}", style = IOSFont.title3, color = c.secondaryText)
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Filled.ChevronRight, null, tint = c.secondaryText.copy(alpha = 0.5f))
        }
        Box(Modifier.padding(start = 42.dp).fillMaxWidth().height(0.5.dp).background(c.primaryText.copy(alpha = 0.1f)))
    }
}

@Composable
private fun EmptyLibrary() {
    val c = Cisum.colors
    Column(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(Icons.Filled.LibraryMusic, null, tint = c.secondaryText, modifier = Modifier.size(44.dp))
        Text("Your Library is empty", style = IOSFont.title3, fontWeight = FontWeight.Bold, color = c.primaryText)
        Text(
            "Import playlists from Spotify, YouTube or Apple Music, or make your own. Their songs, albums and artists show up here.",
            style = IOSFont.subheadline, color = c.secondaryText, textAlign = TextAlign.Center,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Pill("Import Playlist", filled = true)
            Pill("New Playlist", filled = false)
        }
    }
}

@Composable
private fun Pill(text: String, filled: Boolean) {
    val c = Cisum.colors
    Box(
        Modifier
            .background(if (filled) c.primaryText else c.primaryText.copy(alpha = 0.1f), RoundedCornerShape(50))
            .clickable { }
            .padding(horizontal = 16.dp, vertical = 9.dp)
    ) {
        Text(text, style = IOSFont.subheadline, fontWeight = FontWeight.SemiBold, color = if (filled) c.bg else c.primaryText)
    }
}
