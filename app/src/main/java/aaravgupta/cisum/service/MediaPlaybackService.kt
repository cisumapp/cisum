package aaravgupta.cisum.service

import aaravgupta.cisum.perf.Perf
import aaravgupta.cisum.service.stream.RangeChunkingDataSource
import aaravgupta.cisum.service.stream.StreamUrlResolver
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import dagger.hilt.android.AndroidEntryPoint
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.cache.CacheWriter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import javax.inject.Inject

/**
 * The player. Stream path, outermost first:
 *  1. [ResolvingDataSource]: `cisum://watch?v=…` → googlevideo URL via [StreamUrlResolver], when
 *     ExoPlayer opens the item (so queued URLs never go stale).
 *  2. [CacheDataSource]: every byte played lands on disk, keyed by video + format; replays and
 *     seeks back are local reads.
 *  3. [RangeChunkingDataSource]: 1 MB ranges, which googlevideo serves at line rate.
 *  4. HTTP.
 */
@OptIn(UnstableApi::class)
@AndroidEntryPoint
class MediaPlaybackService : MediaSessionService() {
    @Inject lateinit var resolver: StreamUrlResolver
    @Inject lateinit var cache: Cache

    private lateinit var player: ExoPlayer
    private var mediaSession: MediaSession? = null
    private lateinit var cached: CacheDataSource.Factory
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var precache: Job? = null

    override fun onCreate() {
        super.onCreate()

        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(USER_AGENT)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(8_000)
        cached = CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(RangeChunkingDataSource.Factory(http, CHUNK_BYTES))
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        val resolving = ResolvingDataSource.Factory(cached) { spec ->
            val videoId = StreamUrlResolver.videoIdIn(spec.uri) ?: return@Factory spec
            // ExoPlayer's loader thread, never the main thread: blocking here is what it expects.
            val stream = runBlocking { resolver.resolve(videoId) }
            spec.buildUpon().setUri(stream.url).setKey(cacheKey(videoId, stream.url)).build()
        }

        // Start after 0.5 s of audio instead of 2.5 s: the first chunk arrives at line rate, so
        // waiting for more only delays the first sound. Resume after a stall with 2 s in hand.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(DefaultLoadControl.DEFAULT_MIN_BUFFER_MS, 120_000, 500, 2_000)
            .build()

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(resolving))
            .setLoadControl(loadControl)
            .setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).setUsage(C.USAGE_MEDIA).build(),
                /* handleAudioFocus = */ true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_BUFFERING) Perf.playStage("buffering")
                if (state == Player.STATE_READY) Perf.playStage("ready")
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) { Perf.playStage("playing"); Perf.playRequestedAt = 0 }
            }

            override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_SEEK) Perf.playRequestedAt = android.os.SystemClock.elapsedRealtime() // a skip
                // Resolve the next track and put its first bytes on disk while this one plays, so a
                // skip starts from the cache instead of a new connection (~1.8 s on the emulator).
                precache?.cancel()
                val next = player.nextMediaItemIndex.takeIf { it != C.INDEX_UNSET } ?: return
                val nextId = player.getMediaItemAt(next).localConfiguration?.uri?.let(StreamUrlResolver::videoIdIn) ?: return
                resolver.prefetch(nextId)
                precache = scope.launch { precacheStart(nextId) }
            }
        })

        mediaSession = MediaSession.Builder(this, player).build()
    }

    /** The first [PRECACHE_BYTES] of [videoId] into the cache, after the current track has a head start. */
    private suspend fun precacheStart(videoId: String) {
        delay(3_000) // let the playing track take the bandwidth first
        val stream = runCatching { resolver.resolve(videoId) }.getOrNull() ?: return
        val spec = DataSpec.Builder().setUri(stream.url).setKey(cacheKey(videoId, stream.url)).setLength(PRECACHE_BYTES).build()
        val writer = CacheWriter(cached.createDataSource(), spec, null, null)
        currentCoroutineContext()[Job]?.invokeOnCompletion { writer.cancel() }
        runCatching { writer.cache() }
            .onSuccess { android.util.Log.i(Perf.TAG, "precached $videoId ${PRECACHE_BYTES / 1024} KB") }
    }

    /** The URL changes on every resolve; the bytes for a video's format do not. */
    private fun cacheKey(videoId: String, url: String) =
        "yt:$videoId:${android.net.Uri.parse(url).getQueryParameter("itag") ?: "0"}"

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }

    private companion object {
        const val CHUNK_BYTES = 1L * 1024 * 1024
        const val PRECACHE_BYTES = 512L * 1024 // ~30 s of 128 kbps AAC
        const val USER_AGENT = "Mozilla/5.0"
    }
}
