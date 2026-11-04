package aaravgupta.cisum.perf

import android.app.Activity
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.FrameMetrics
import androidx.tracing.trace

/**
 * Performance logging, all under logcat tag "Perf" (and Perfetto sections via androidx.tracing):
 *  - `frames screen=… n=… jank=…% slow=… frozen=… p50/p90/p99/max` every 2 s per screen, from the
 *    platform's FrameMetrics (no extra dependency);
 *  - `swift <method> <ms>` for every bridge call, `js <ms>` for WebView evaluations;
 *  - `mark <name> +<ms>` startup milestones measured from process start.
 * Read with: adb logcat -s Perf
 */
object Perf {
    const val TAG = "Perf"
    private val processStart = SystemClock.elapsedRealtime()

    /** The screen the user is on, set by the shell; frames are bucketed by it. */
    @Volatile var screen: String = "home"

    /** A/B switch for measuring: `adb shell am start -n aaravgupta.cisum/.MainActivity --ez glass false`. */
    @Volatile var glassEnabled: Boolean = true

    /** When the current play was requested; the player logs its stages against it. */
    @Volatile var playRequestedAt = 0L
    fun playStage(stage: String) {
        if (playRequestedAt > 0) Log.i(TAG, "play $stage +${SystemClock.elapsedRealtime() - playRequestedAt}ms")
    }

    fun mark(name: String) = Log.i(TAG, "mark $name +${SystemClock.elapsedRealtime() - processStart}ms")

    inline fun <T> time(label: String, crossinline block: () -> T): T {
        val start = SystemClock.elapsedRealtimeNanos()
        return try {
            trace(label) { block() }
        } finally {
            val ms = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
            Log.i(TAG, "$label ${"%.1f".format(ms)}ms${if (ms > 16) " (over a frame)" else ""}")
        }
    }

    private val frames = HashMap<String, MutableList<Float>>()
    private val worker = HandlerThread("perf-frames").apply { start() }
    private val handler = Handler(worker.looper)

    fun installFrameMetrics(activity: Activity) {
        val budgetMs = 1000f / (activity.display?.refreshRate ?: 60f)
        activity.window.addOnFrameMetricsAvailableListener({ _, metrics, _ ->
            val ms = metrics.getMetric(FrameMetrics.TOTAL_DURATION) / 1_000_000f
            synchronized(frames) { frames.getOrPut(screen) { ArrayList() }.add(ms) }
        }, handler)
        fun flush() {
            val snapshot = synchronized(frames) { frames.toMap().also { frames.clear() } }
            snapshot.forEach { (screen, list) -> report(screen, list, budgetMs) }
            handler.postDelayed(::flush, 2000)
        }
        handler.postDelayed(::flush, 2000)
    }

    private fun report(screen: String, list: List<Float>, budgetMs: Float) {
        if (list.isEmpty()) return
        val sorted = list.sorted()
        fun p(q: Double) = sorted[((sorted.size - 1) * q).toInt()]
        val jank = list.count { it > budgetMs }
        Log.i(
            TAG,
            "frames screen=$screen n=${list.size} jank=${100 * jank / list.size}% slow(>50ms)=${list.count { it > 50 }} " +
                "frozen(>700ms)=${list.count { it > 700 }} p50=${"%.1f".format(p(0.5))} p90=${"%.1f".format(p(0.9))} " +
                "p99=${"%.1f".format(p(0.99))} max=${"%.1f".format(sorted.last())} budget=${"%.1f".format(budgetMs)}",
        )
    }
}
