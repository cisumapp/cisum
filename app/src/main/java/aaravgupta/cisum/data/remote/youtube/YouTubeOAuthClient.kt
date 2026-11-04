package aaravgupta.cisum.data.remote.youtube

import aaravgupta.cisum.data.session.SessionStore
// import aaravgupta.youtubesdk.YouTube
// import aaravgupta.youtubesdk.youtubeOAuth.YouTubeOAuthClient as SdkOAuthClient
import kotlinx.coroutines.flow.first

class YouTubeOAuthClient(
    private val sessionStore: SessionStore,
    private val youTube: Any? = null // YouTube
) {
    suspend fun validateSession(
        regionCode: String = "US",
        languageCode: String = "en"
    ): Boolean {
        return false // TODO: stub
        /*
        return runCatching {
            SdkOAuthClient().validateSession()
        }.getOrDefault(false)
        */
    }

    suspend fun saveCookies(cookie: String) {
        val normalizedCookie = cookie.trim()
        if (normalizedCookie.isBlank()) {
            return
        }

        // SdkOAuthClient.saveCookies(normalizedCookie)
        sessionStore.saveOauthCookie(normalizedCookie)
        // youTube.cookies = normalizedCookie
    }

    suspend fun loadCookies(): String? {
        val sdkCookie: String? = null // SdkOAuthClient.loadCookies()
        val sessionCookie = sessionStore.oauthCookie.first()
        val resolvedCookie = if (!sdkCookie.isNullOrBlank()) {
            sdkCookie
        } else {
            sessionCookie
        }

        if (!resolvedCookie.isNullOrBlank()) {
            if (sessionCookie != resolvedCookie) {
                sessionStore.saveOauthCookie(resolvedCookie)
            }
            /*
            if (youTube.cookies != resolvedCookie) {
                youTube.cookies = resolvedCookie
            }
            */
        }

        return resolvedCookie
    }

    suspend fun logout() {
        // SdkOAuthClient.logout()
        sessionStore.clearSession()
        // youTube.cookies = null
    }
}