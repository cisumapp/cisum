package aaravgupta.cisum.data.remote.swift

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.swift.SwiftBridge
import org.json.JSONArray
import org.json.JSONObject

/** Typed Kotlin view of the Swift SDK calls the screens use. Models mirror YouTubeSDK's. */
data class ChartItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val rank: String,
    val thumbnailUrl: String?,
    val type: String, // song | video | artist
)

data class MusicArtist(val id: String, val name: String, val thumbnailUrl: String?, val subtitle: String?)
data class MusicPlaylist(val id: String, val title: String, val author: String?, val thumbnailUrl: String?)

object SwiftCatalog {
    suspend fun searchSongs(query: String): List<Track> =
        SwiftBridge.call("youtube.searchSongs", "query" to query).toArray().objects().map { it.toTrack() }

    suspend fun search(query: String): List<Track> =
        SwiftBridge.youtubeSearch(query).objects().map { it.toTrack() }

    suspend fun searchArtists(query: String): List<MusicArtist> =
        SwiftBridge.call("youtube.searchArtists", "query" to query).toArray().objects().map {
            MusicArtist(it.getString("id"), it.optString("name"), it.str("thumbnailURL"), it.str("subscriberCount"))
        }

    suspend fun searchPlaylists(query: String): List<MusicPlaylist> =
        SwiftBridge.call("youtube.searchPlaylists", "query" to query).toArray().objects().map {
            MusicPlaylist(it.getString("id"), it.optString("title"), it.str("author"), it.str("thumbnailURL"))
        }

    suspend fun suggestions(query: String): List<String> =
        SwiftBridge.call("youtube.suggestions", "query" to query).toArray().let { a -> (0 until a.length()).map { a.getString(it) } }

    /** kind: topSongs | topVideos | topArtists | trending */
    suspend fun charts(kind: String, country: String = "US"): List<ChartItem> =
        SwiftBridge.call("youtube.charts", "kind" to kind, "country" to country).toArray().objects().map {
            ChartItem(
                id = it.getString("id"),
                title = it.optString("title"),
                subtitle = it.optString("subtitle"),
                rank = it.optString("rank"),
                thumbnailUrl = it.str("thumbnailURL"),
                type = it.optString("type"),
            )
        }
}

fun ChartItem.toTrack() = Track(
    id = id, title = title, artist = subtitle, artworkUrl = thumbnailUrl, durationMs = 0, streamUrl = ""
)

/** A YouTubeMusicSong as JSON → Track. */
fun JSONObject.toTrack(): Track {
    val artists = optJSONArray("artists")
    return Track(
        id = getString("videoId"),
        title = optString("title"),
        artist = (0 until (artists?.length() ?: 0)).joinToString(", ") { artists!!.getString(it) },
        artworkUrl = str("thumbnailURL"),
        durationMs = (optDouble("duration", 0.0) * 1000).toLong(),
        streamUrl = "",
        album = str("album"),
        isExplicit = optBoolean("isExplicit"),
    )
}

private fun String.toArray() = JSONArray(this)
private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
private fun JSONObject.str(key: String) = optString(key).takeIf { it.isNotEmpty() && it != "null" }
