package aaravgupta.cisum.di

import aaravgupta.cisum.data.remote.itunes.iTunesClient
import aaravgupta.cisum.data.remote.youtube.YouTubeClient
import aaravgupta.cisum.data.remote.youtube.YouTubeMusicClient
import aaravgupta.cisum.data.remote.youtube.YouTubeOAuthClient
import aaravgupta.cisum.data.repository.InMemoryMusicRepository
import aaravgupta.cisum.data.repository.ListeningHistory
import aaravgupta.cisum.data.session.SessionStore
import aaravgupta.cisum.domain.repository.MusicRepository
import aaravgupta.cisum.service.PlaybackController
import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import javax.inject.Qualifier
import javax.inject.Singleton
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache

/** A scope that outlives screens: playback resolution, history writes, session checks. */
@Qualifier @Retention(AnnotationRetention.BINARY) annotation class ApplicationScope

// KSP needs explicit return types on @Provides; inferred ones resolve to error.NonExistentClass.
/** App-wide singletons that predate DI and so are built here rather than by @Inject. */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides @Singleton @ApplicationScope
    fun applicationScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Provides @Singleton fun sessionStore(@ApplicationContext context: Context): SessionStore = SessionStore(context)
    @Provides @Singleton fun playbackController(@ApplicationContext context: Context): PlaybackController = PlaybackController(context)
    @Provides @Singleton fun youTubeClient(): YouTubeClient = YouTubeClient(null)
    @Provides @Singleton fun youTubeMusicClient(youTube: YouTubeClient): YouTubeMusicClient = YouTubeMusicClient(youTube, null)
    @Provides @Singleton fun youTubeOAuthClient(sessions: SessionStore): YouTubeOAuthClient = YouTubeOAuthClient(sessions, null)
    @Provides @Singleton fun iTunesClient(): iTunesClient = iTunesClient()

    /** Played audio on disk, LRU at 512 MB. One instance per directory, so a singleton. */
    @OptIn(UnstableApi::class)
    @Provides @Singleton
    fun audioCache(@ApplicationContext context: Context): Cache = SimpleCache(
        java.io.File(context.cacheDir, "audio"),
        LeastRecentlyUsedCacheEvictor(512L * 1024 * 1024),
        StandaloneDatabaseProvider(context),
    )

    @Provides @Singleton
    fun musicRepository(youTube: YouTubeClient, history: ListeningHistory): MusicRepository =
        InMemoryMusicRepository(youTube, history)
}
