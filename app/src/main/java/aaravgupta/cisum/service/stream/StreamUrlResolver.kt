package aaravgupta.cisum.service.stream

import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.perf.Perf
import aaravgupta.cisum.swift.SwiftBridge
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import javax.inject.Inject
import javax.inject.Singleton

/** A resolved stream, and what to tell the player's source line about it. */
data class ResolvedStream(val url: String, val mimeType: String?, val codec: String?, val durationMs: Long)

/**
 * `cisum://watch?v=<videoId>` → a googlevideo URL, through the Swift resolver.
 *
 * Queue items carry the cisum URI, not a stream URL: signed URLs expire after a few hours, so
 * resolving when ExoPlayer actually opens the item keeps any queue playable, and a track that is
 * never reached is never resolved. Answers are reused for [TTL_MS] (well inside the expiry), and
 * concurrent asks for one track share one Swift call, so a prefetch and the player's own open
 * cost a single resolve.
 */
@Singleton
class StreamUrlResolver @Inject constructor(
    private val repository: MusicRepository,
    @aaravgupta.cisum.di.ApplicationScope private val scope: CoroutineScope,
) {
    private class Entry(val at: Long, val stream: Deferred<ResolvedStream>)
    private val entries = HashMap<String, Entry>()

    /** Starts resolving ahead of time; the player's open then finds it done or in flight. */
    fun prefetch(videoId: String) { request(videoId) }

    suspend fun resolve(videoId: String): ResolvedStream = request(videoId).await()

    private fun request(videoId: String): Deferred<ResolvedStream> {
        val now = SystemClock.elapsedRealtime()
        val fresh = CompletableDeferred<ResolvedStream>()
        synchronized(entries) {
            entries[videoId]?.takeIf { now - it.at < TTL_MS }?.let { return it.stream }
            entries[videoId] = Entry(now, fresh)
        }
        scope.async {
            runCatching {
                val json = SwiftBridge.youtubeResolve(videoId, preferAudio = true)
                fun field(k: String) = json.optString(k).takeIf { it.isNotEmpty() && it != "null" }
                ResolvedStream(
                    url = field("url") ?: error("no playable stream for $videoId"),
                    mimeType = field("mimeType"),
                    codec = field("codec"),
                    durationMs = (json.optDouble("duration", 0.0) * 1000).toLong(),
                )
            }.onSuccess { stream ->
                Perf.playStage("resolved")
                fresh.complete(stream)
                // The player's source line ("YouTube Music · audio/mp4 · mp4a.40.2") and duration.
                repository.nowPlaying.value?.takeIf { it.id == videoId }?.let {
                    repository.setNowPlaying(it.copy(
                        streamUrl = stream.url, sourceName = "YouTube Music", mimeType = stream.mimeType, codec = stream.codec,
                        durationMs = it.durationMs.takeIf { d -> d > 0 } ?: stream.durationMs,
                    ))
                }
            }.onFailure { e ->
                Log.w(Perf.TAG, "resolve $videoId failed", e)
                synchronized(entries) { entries.remove(videoId) }
                fresh.completeExceptionally(e)
            }
        }
        return fresh
    }

    companion object {
        const val SCHEME = "cisum"
        private const val TTL_MS = 60 * 60 * 1000L

        fun uriFor(videoId: String): Uri = Uri.parse("$SCHEME://watch?v=$videoId")
        fun videoIdIn(uri: Uri): String? = if (uri.scheme == SCHEME) uri.getQueryParameter("v") else null
    }
}
