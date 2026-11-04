package aaravgupta.cisum.data.session

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.sessionDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "cisum_session"
)

class SessionStore(
    private val context: Context
) {
    private object Keys {
        val oauthCookie = stringPreferencesKey("oauth_cookie")
        val isLoggedIn = booleanPreferencesKey("is_logged_in")
    }

    val oauthCookie: Flow<String?> = context.sessionDataStore
        .data
        .map { preferences -> preferences[Keys.oauthCookie] }

    val isLoggedIn: Flow<Boolean> = context.sessionDataStore
        .data
        .map { preferences -> preferences[Keys.isLoggedIn] ?: false }

    suspend fun saveOauthCookie(cookie: String) {
        context.sessionDataStore.edit { preferences ->
            preferences[Keys.oauthCookie] = cookie
            preferences[Keys.isLoggedIn] = true
        }
    }

    suspend fun clearSession() {
        context.sessionDataStore.edit { preferences ->
            preferences.remove(Keys.oauthCookie)
            preferences[Keys.isLoggedIn] = false
        }
    }
}
