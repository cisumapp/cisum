package aaravgupta.cisum.swift

import aaravgupta.cisum.perf.Perf
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** A Swift error from a bridged call. */
class SwiftBridgeException(message: String) : RuntimeException(message)

/**
 * cisum's Swift SDKs (StreamingKit/AndroidBridge → libCisumBridge.so), called over JNI.
 *
 * `call(method, args)` suspends: Swift runs the call as a Task and calls back when it is done, so
 * no thread is held while the network works. Cancelling the coroutine cancels the Swift Task.
 */
object SwiftBridge {
    init {
        Perf.time("loadLibrary(CisumBridge)") {
            System.loadLibrary("c++_shared")
            System.loadLibrary("CisumBridge")
        }
    }

    /** Called by Swift, once, from a Swift thread. Kept by the R8 rule for this package. */
    fun interface NativeCallback { fun onResult(json: String?, error: String?) }

    private external fun nativeCallAsync(method: String, argsJson: String, callback: NativeCallback): Long
    private external fun nativeCancel(handle: Long)

    suspend fun call(method: String, vararg args: Pair<String, Any?>): String {
        val json = JSONObject()
        args.forEach { (key, value) -> if (value != null) json.put(key, value.toString()) }
        val started = SystemClock.elapsedRealtime()
        return suspendCancellableCoroutine { cont ->
            val handle = nativeCallAsync(method, json.toString()) { result, error ->
                Log.i(Perf.TAG, "swift $method ${SystemClock.elapsedRealtime() - started}ms${if (error != null) " error=$error" else ""}")
                when {
                    result != null -> cont.resume(result)
                    cont.isActive -> cont.resumeWithException(SwiftBridgeException(error ?: "no result"))
                }
            }
            if (handle == 0L) cont.resumeWithException(SwiftBridgeException("$method: could not start"))
            cont.invokeOnCancellation { nativeCancel(handle) }
        }
    }

    // YouTubeSDK
    suspend fun youtubeSearch(query: String): JSONArray =
        JSONArray(call("youtube.search", "query" to query))

    /** Keys: videoId, title, channel, duration, url, hls, formats. */
    suspend fun youtubeResolve(videoId: String, preferAudio: Boolean = true): JSONObject =
        JSONObject(call("youtube.resolve", "videoId" to videoId, "preferAudio" to preferAudio))

    // iTunesKit
    suspend fun itunesSearch(term: String): JSONArray = JSONArray(call("itunes.search", "term" to term))
    suspend fun itunesLookup(id: String): JSONObject = JSONObject(call("itunes.lookup", "id" to id))

    // LyricsKit (LRCLIB); null when no lyrics match.
    suspend fun lyrics(track: String, artist: String, album: String? = null, durationSeconds: Int? = null): JSONObject? =
        call("lyrics.best", "track" to track, "artist" to artist, "album" to album, "duration" to durationSeconds)
            .let { if (it == "null") null else JSONObject(it) }

    // SpotifySDK (anonymous web-player token)
    suspend fun spotifySearch(query: String): JSONObject = JSONObject(call("spotify.search", "query" to query))

    /** Keys: trackId, url (MP4 or null). Pass trackId, or title + artist to look it up. */
    suspend fun spotifyCanvas(trackId: String? = null, title: String? = null, artist: String? = null): JSONObject =
        JSONObject(call("spotify.canvas", "trackId" to trackId, "title" to title, "artist" to artist))
}
