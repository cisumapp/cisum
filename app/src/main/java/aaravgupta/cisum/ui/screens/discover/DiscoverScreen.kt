package aaravgupta.cisum.ui.screens.discover

import aaravgupta.cisum.ui.components.NavigationBarView
import aaravgupta.cisum.ui.components.StatusMessage
import aaravgupta.cisum.ui.components.TrackListItem
import aaravgupta.cisum.ui.theme.Cisum
import aaravgupta.cisum.ui.theme.IOSFont
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.navigation.compose.hiltViewModel

/** DiscoverView.swift: ranked chart sections. */
@Composable
fun DiscoverScreen(onProfile: () -> Unit, viewModel: DiscoverViewModel = hiltViewModel()) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val c = Cisum.colors

    NavigationBarView(title = "Discover", onProfile = onProfile) {
        if (ui.isLoading && ui.sections.isEmpty()) item { StatusMessage("Loading Charts...") }
        ui.errorMessage?.let { item { StatusMessage("Unable to Load Charts\n$it") } }

        ui.sections.forEach { section ->
            item(key = "h-${section.id}") {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 10.dp)) {
                    Text(section.title, style = IOSFont.title3, fontWeight = FontWeight.SemiBold, color = c.primaryText)
                    Text(section.subtitle, style = IOSFont.caption, color = c.secondaryText)
                }
            }
            itemsIndexed(section.items, key = { _, it -> "${section.id}-${it.id}" }) { index, item ->
                Row(
                    Modifier.clickable {
                        // Songs and videos play; artists open their page (not ported yet).
                        if (item.type == "song" || item.type == "video") viewModel.play(item, section)
                    },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "#${index + 1}",
                        style = IOSFont.caption,
                        fontWeight = FontWeight.Bold,
                        color = c.secondaryText,
                        modifier = Modifier.padding(start = 16.dp).width(34.dp),
                    )
                    TrackListItem(
                        item.title,
                        item.subtitle,
                        item.thumbnailUrl,
                        artworkShape = if (item.type == "artist") CircleShape else RoundedCornerShape(8.dp),
                    )
                }
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}
