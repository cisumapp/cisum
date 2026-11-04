package aaravgupta.cisum.data.repository

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.di.ApplicationScope
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * What the user played, newest first: iOS's ListeningHistoryEntry, which feeds Home's "Jump Back In".
 * Loaded and written off the main thread.
 * ponytail: one JSON file, rewritten on each play, capped at 100. Room if it needs queries.
 */
@Singleton
class ListeningHistory @Inject constructor(
    @ApplicationContext context: Context,
    @ApplicationScope private val scope: CoroutineScope,
) {
    private val file = File(context.filesDir, "listening_history.json")
    private val state = MutableStateFlow<List<Track>>(emptyList())
    val entries: StateFlow<List<Track>> = state.asStateFlow()

    init {
        scope.launch(Dispatchers.IO) {
            val loaded = load()
            state.update { current -> (current + loaded).distinctBy { it.id }.take(100) }
        }
    }

    fun record(track: Track) {
        state.update { (listOf(track) + it.filterNot { e -> e.id == track.id }).take(100) }
        val snapshot = state.value
        scope.launch(Dispatchers.IO) { runCatching { file.writeText(JSONArray(snapshot.map { it.toJson() }).toString()) } }
    }

    private fun load(): List<Track> = runCatching {
        val a = JSONArray(file.readText())
        (0 until a.length()).map { a.getJSONObject(it).toTrackEntry() }
    }.getOrDefault(emptyList())

    private fun Track.toJson() = JSONObject()
        .put("id", id).put("title", title).put("artist", artist).put("artworkUrl", artworkUrl)
        .put("durationMs", durationMs).put("album", album).put("isExplicit", isExplicit)

    private fun JSONObject.toTrackEntry() = Track(
        id = getString("id"),
        title = optString("title"),
        artist = optString("artist"),
        artworkUrl = optString("artworkUrl").takeIf { it.isNotEmpty() && it != "null" },
        durationMs = optLong("durationMs"),
        streamUrl = "",
        album = optString("album").takeIf { it.isNotEmpty() && it != "null" },
        isExplicit = optBoolean("isExplicit"),
    )
}
