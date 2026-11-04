package aaravgupta.cisum.service.stream

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import android.net.Uri
import kotlin.math.min

/**
 * Reads a stream as consecutive bounded `Range` requests of [chunkBytes] instead of one open-ended
 * request. googlevideo paces an open-ended response to about playback speed, which leaves no
 * bandwidth to build a buffer; bounded ranges are served at line rate. (Observed by BitChord's
 * authors and the same reason yt-dlp downloads in chunks.) Callers see one continuous read.
 */
@OptIn(UnstableApi::class)
class RangeChunkingDataSource(
    private val upstream: DataSource,
    private val chunkBytes: Long,
) : DataSource {
    private var spec: DataSpec? = null
    private var position = 0L          // absolute offset of the next byte
    private var end = C.LENGTH_UNSET.toLong() // absolute end, if the caller bounded the read
    private var chunkLeft = 0L
    private var lastChunk = false
    private var open = false
    private var firstChunk = true

    override fun addTransferListener(transferListener: TransferListener) = upstream.addTransferListener(transferListener)

    override fun open(dataSpec: DataSpec): Long {
        spec = dataSpec
        position = dataSpec.position
        end = if (dataSpec.length != C.LENGTH_UNSET.toLong()) dataSpec.position + dataSpec.length else C.LENGTH_UNSET.toLong()
        lastChunk = false
        firstChunk = true
        openChunk()
        return dataSpec.length // unknown stays unknown; the last short chunk ends the read
    }

    private fun openChunk() {
        val base = spec!!
        // The first range is small so playback can start on it (0.5 s of AAC is ~8 KB); the rest
        // are full size. Measured: a 1 MB first range was ~2 s of the tap-to-sound time.
        val size = if (firstChunk) min(FIRST_CHUNK_BYTES, chunkBytes) else chunkBytes
        firstChunk = false
        val want = if (end == C.LENGTH_UNSET.toLong()) size else min(size, end - position)
        val t0 = android.os.SystemClock.elapsedRealtime()
        val opened = upstream.open(base.subrange(position - base.position, want))
        if (firstChunkLogged.compareAndSet(false, true) || want <= FIRST_CHUNK_BYTES)
            android.util.Log.i(aaravgupta.cisum.perf.Perf.TAG, "http open @$position len=$want ${android.os.SystemClock.elapsedRealtime() - t0}ms")
        open = true
        chunkLeft = if (opened == C.LENGTH_UNSET.toLong()) want else opened
        // "Content-Range: bytes 0-1048575/3456789" gives the total, so the read stops exactly at
        // the end instead of asking for a range past it (416).
        if (end == C.LENGTH_UNSET.toLong()) {
            upstream.responseHeaders.entries.firstOrNull { it.key.equals("Content-Range", ignoreCase = true) }
                ?.value?.firstOrNull()?.substringAfterLast('/')?.toLongOrNull()?.let { end = it }
        }
        // The server gave us less than we asked for: this is the end of the resource.
        if (chunkLeft < want || (end != C.LENGTH_UNSET.toLong() && position + chunkLeft >= end)) lastChunk = true
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (chunkLeft == 0L) {
            if (lastChunk) return C.RESULT_END_OF_INPUT
            upstream.close(); open = false
            openChunk()
        }
        val n = upstream.read(buffer, offset, min(length.toLong(), chunkLeft).toInt())
        if (n == C.RESULT_END_OF_INPUT) { lastChunk = true; chunkLeft = 0; return C.RESULT_END_OF_INPUT }
        position += n
        chunkLeft -= n
        return n
    }

    override fun getUri(): Uri? = upstream.uri
    override fun getResponseHeaders(): Map<String, List<String>> = upstream.responseHeaders

    override fun close() {
        if (open) { open = false; upstream.close() }
    }

    private companion object {
        const val FIRST_CHUNK_BYTES = 128L * 1024
        val firstChunkLogged = java.util.concurrent.atomic.AtomicBoolean(false)
    }

    class Factory(private val upstream: DataSource.Factory, private val chunkBytes: Long) : DataSource.Factory {
        override fun createDataSource(): DataSource = RangeChunkingDataSource(upstream.createDataSource(), chunkBytes)
    }
}
