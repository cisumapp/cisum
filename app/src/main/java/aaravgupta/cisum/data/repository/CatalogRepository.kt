package aaravgupta.cisum.data.repository

import aaravgupta.cisum.data.model.Track
import aaravgupta.cisum.data.remote.swift.ChartItem
import aaravgupta.cisum.data.remote.swift.MusicArtist
import aaravgupta.cisum.data.remote.swift.MusicPlaylist
import aaravgupta.cisum.data.remote.swift.SwiftCatalog
import aaravgupta.cisum.di.ApplicationScope
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Catalog reads over the Swift SDKs. Charts are cached like iOS's HomeFeedCache / DiscoverCache:
 * memory first, then a file younger than 6 h, then the network. Concurrent asks for the same chart
 * share one request, so Home and Discover opening together cost one call per chart, not two.
 */
@Singleton
class CatalogRepository @Inject constructor(
    @ApplicationContext context: Context,
    @ApplicationScope private val scope: CoroutineScope,
) {
    private val cacheDir = File(context.cacheDir, "charts").apply { mkdirs() }
    private val memory = HashMap<String, List<ChartItem>>()
    private val inFlight = HashMap<String, Deferred<List<ChartItem>>>()
    private val lock = Mutex()

    /** kind: topSongs | topVideos | topArtists | trending */
    suspend fun charts(kind: String, country: String = "US", force: Boolean = false): List<ChartItem> {
        val key = "$kind-$country"
        val request = lock.withLock {
            if (!force) memory[key]?.let { return it }
            inFlight[key] ?: scope.async {
                try {
                    (if (force) null else readCache(key)) ?: SwiftCatalog.charts(kind, country).also { writeCache(key, it) }
                } finally {
                    lock.withLock { inFlight.remove(key) }
                }
            }.also { inFlight[key] = it }
        }
        return request.await().also { lock.withLock { memory[key] = it } }
    }

    suspend fun searchSongs(query: String): List<Track> = SwiftCatalog.searchSongs(query)
    suspend fun searchArtists(query: String): List<MusicArtist> = SwiftCatalog.searchArtists(query)
    suspend fun searchPlaylists(query: String): List<MusicPlaylist> = SwiftCatalog.searchPlaylists(query)
    suspend fun suggestions(query: String): List<String> = SwiftCatalog.suggestions(query)

    private suspend fun readCache(key: String): List<ChartItem>? = withContext(Dispatchers.IO) {
        val f = File(cacheDir, "$key.json")
        if (!f.exists() || System.currentTimeMillis() - f.lastModified() > 6 * 3600_000L) return@withContext null
        runCatching {
            val a = JSONArray(f.readText())
            (0 until a.length()).map { i ->
                a.getJSONObject(i).let { ChartItem(it.getString("id"), it.optString("title"), it.optString("subtitle"), it.optString("rank"), it.optString("thumbnailUrl").ifEmpty { null }, it.optString("type")) }
            }
        }.getOrNull()
    }

    private suspend fun writeCache(key: String, items: List<ChartItem>) = withContext(Dispatchers.IO) {
        runCatching {
            File(cacheDir, "$key.json").writeText(JSONArray(items.map {
                JSONObject().put("id", it.id).put("title", it.title).put("subtitle", it.subtitle).put("rank", it.rank)
                    .put("thumbnailUrl", it.thumbnailUrl ?: "").put("type", it.type)
            }).toString())
        }
    }
}
