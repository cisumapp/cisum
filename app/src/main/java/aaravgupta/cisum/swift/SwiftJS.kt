package aaravgupta.cisum.swift

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONTokener
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * JavaScript for the Swift SDKs (Android has no JavaScriptCore). Swift calls [evaluate] over JNI
 * from its own threads; this runs the script in a hidden WebView that already holds YouTube's EJS
 * challenge solver (assets/yt.solver.*.min.js), and blocks the caller until the result comes back.
 *
 * ponytail: one WebView, UI-thread round trips. First version, per plan; move to an off-main
 * engine once it works end to end.
 */
@SuppressLint("SetJavaScriptEnabled")
object SwiftJS {
    private const val TAG = "SwiftJS"
    private val main = Handler(Looper.getMainLooper())
    private val ready = CountDownLatch(1)
    private var webView: WebView? = null

    fun install(context: Context) = main.post {
        val app = context.applicationContext
        val lib = app.assets.open("yt.solver.lib.min.js").bufferedReader().use { it.readText() }
        val core = app.assets.open("yt.solver.core.min.js").bufferedReader().use { it.readText() }
        webView = WebView(app).apply {
            settings.javaScriptEnabled = true
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String?) {
                    if (ready.count == 0L) return // fires more than once; load the solver once
                    // Same load order as the JavaScriptCore path in YouTubeJSResolver.
                    view.evaluateJavascript(lib, null)
                    view.evaluateJavascript("var meriyah = lib.meriyah; var astring = lib.astring;", null)
                    view.evaluateJavascript(core, null)
                    view.evaluateJavascript("typeof jsc") {
                        aaravgupta.cisum.perf.Perf.mark("js solver ready ($it)")
                        ready.countDown()
                    }
                }
            }
            loadDataWithBaseURL("https://www.youtube.com/", "<html></html>", "text/html", "utf-8", null)
        }
    }

    /** Called from Swift. Returns the last expression's string value, or null. Never on the main thread. */
    @JvmStatic
    fun evaluate(script: String): String? {
        if (Looper.myLooper() == Looper.getMainLooper()) return null // would deadlock
        if (!ready.await(30, TimeUnit.SECONDS)) return null
        val started = android.os.SystemClock.elapsedRealtime()
        val done = CountDownLatch(1)
        var raw: String? = null
        main.post {
            webView?.evaluateJavascript(script) { raw = it; done.countDown() } ?: done.countDown()
        }
        if (!done.await(30, TimeUnit.SECONDS)) return null
        // evaluateJavascript hands back the value JSON-encoded: "\"abc\"" for a string, "null" otherwise.
        return runCatching { JSONTokener(raw ?: "null").nextValue() as? String }.getOrNull()
            .also { Log.i(aaravgupta.cisum.perf.Perf.TAG, "js ${android.os.SystemClock.elapsedRealtime() - started}ms ${script.length} chars") }
    }
}
