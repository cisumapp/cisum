package aaravgupta.cisum

import aaravgupta.cisum.data.remote.youtube.YouTubeOAuthClient
import aaravgupta.cisum.di.ApplicationScope
import aaravgupta.cisum.perf.Perf
import aaravgupta.cisum.swift.SwiftJS
import android.app.Application
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class cisumApplication : Application() {
    @Inject lateinit var oauth: YouTubeOAuthClient
    @Inject @ApplicationScope lateinit var scope: CoroutineScope

    override fun onCreate() {
        super.onCreate()
        Perf.mark("app.onCreate")
        Perf.time("SwiftJS.install") { SwiftJS.install(this) }
        // visitorData + signature timestamp now, so the first play does not wait on them.
        scope.launch { runCatching { aaravgupta.cisum.swift.SwiftBridge.call("youtube.warmUp") } }
        // A stored YouTube session that no longer validates is dropped, off the main thread.
        scope.launch {
            if (oauth.loadCookies().isNullOrBlank()) return@launch
            if (!oauth.validateSession()) oauth.logout()
        }
    }
}
