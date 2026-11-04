package aaravgupta.cisum.ui.navigation

import aaravgupta.cisum.R
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material.icons.filled.Search
import androidx.compose.ui.graphics.vector.ImageVector

sealed class cisumDestination(
    val route: String,
    @field:StringRes val labelRes: Int,
    val icon: ImageVector
) {
    data object Home : cisumDestination(
        route = "home",
        labelRes = R.string.tab_home,
        icon = Icons.Default.Home
    )

    data object Search : cisumDestination(
        route = "search",
        labelRes = R.string.tab_search,
        icon = Icons.Default.Search
    )

    data object Discover : cisumDestination(
        route = "discover",
        labelRes = R.string.tab_discover,
        icon = Icons.Default.AutoAwesome
    )

    data object Library : cisumDestination(
        route = "library",
        labelRes = R.string.tab_library,
        icon = Icons.Default.LibraryMusic
    )

    data object Profile : cisumDestination(
        route = "profile",
        labelRes = R.string.tab_profile,
        icon = Icons.Default.Person
    )

    data object Player : cisumDestination(
        route = "player",
        labelRes = R.string.tab_now_playing,
        icon = Icons.Default.PlayCircleFilled
    )
}

val topLevelDestinations = listOf(
    cisumDestination.Home,
    cisumDestination.Search,
    cisumDestination.Discover,
    cisumDestination.Library,
    cisumDestination.Profile
)
