package aaravgupta.cisum.ui.screens.profile

import aaravgupta.cisum.data.remote.youtube.YouTubeOAuthClient
import aaravgupta.cisum.data.session.SessionStore
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ProfileUiState(
    val isLoggedIn: Boolean = false,
    val isValidatingSession: Boolean = false,
    val isShowingGoogleSignIn: Boolean = false,
    val statusMessage: String? = null
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val sessionStore: SessionStore,
    private val youTubeOAuthClient: YouTubeOAuthClient
) : ViewModel() {
    private val mutableUiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = mutableUiState.asStateFlow()

    init {
        observeSession()
        validateStoredSession()
    }

    fun startGoogleSignIn() {
        mutableUiState.update { state ->
            state.copy(
                isShowingGoogleSignIn = true,
                statusMessage = null
            )
        }
    }

    fun cancelGoogleSignIn() {
        if (uiState.value.isValidatingSession) {
            return
        }

        mutableUiState.update { state ->
            state.copy(
                isShowingGoogleSignIn = false,
                statusMessage = "Google sign-in canceled."
            )
        }
    }

    fun onGoogleLoginSuccess(cookiePayload: String) {
        viewModelScope.launch {
            val normalizedCookie = cookiePayload.trim()
            if (normalizedCookie.isBlank()) {
                mutableUiState.update { state ->
                    state.copy(statusMessage = "Google login did not return a valid session.")
                }
                return@launch
            }

            mutableUiState.update { state ->
                state.copy(
                    isValidatingSession = true,
                    statusMessage = null
                )
            }

            youTubeOAuthClient.saveCookies(normalizedCookie)
            val isValid = runCatching {
                youTubeOAuthClient.validateSession()
            }.getOrDefault(false)

            if (isValid) {
                mutableUiState.update { state ->
                    state.copy(
                        isValidatingSession = false,
                        isShowingGoogleSignIn = false,
                        statusMessage = "Google account connected."
                    )
                }
            } else {
                youTubeOAuthClient.logout()
                mutableUiState.update { state ->
                    state.copy(
                        isValidatingSession = false,
                        isShowingGoogleSignIn = true,
                        statusMessage = "Login could not be validated. Please try again."
                    )
                }
            }
        }
    }

    fun logoutSession() {
        viewModelScope.launch {
            youTubeOAuthClient.logout()
            mutableUiState.update { state ->
                state.copy(
                    isShowingGoogleSignIn = false,
                    statusMessage = "Logged out successfully."
                )
            }
        }
    }

    private fun observeSession() {
        viewModelScope.launch {
            sessionStore.isLoggedIn.collect { isLoggedIn ->
                mutableUiState.update { state ->
                    state.copy(
                        isLoggedIn = isLoggedIn,
                        isShowingGoogleSignIn = if (isLoggedIn) {
                            false
                        } else {
                            state.isShowingGoogleSignIn
                        }
                    )
                }
            }
        }
    }

    private fun validateStoredSession() {
        viewModelScope.launch {
            val existingCookie = youTubeOAuthClient.loadCookies() ?: sessionStore.oauthCookie.first()
            if (existingCookie.isNullOrBlank()) {
                return@launch
            }

            mutableUiState.update { state ->
                state.copy(
                    isValidatingSession = true,
                    statusMessage = null
                )
            }

            val isValid = runCatching {
                youTubeOAuthClient.validateSession()
            }.getOrDefault(false)

            if (!isValid) {
                youTubeOAuthClient.logout()
                mutableUiState.update { state ->
                    state.copy(
                        isValidatingSession = false,
                        statusMessage = "Saved session expired."
                    )
                }
            } else {
                mutableUiState.update { state ->
                    state.copy(
                        isValidatingSession = false,
                        statusMessage = "Session restored."
                    )
                }
            }
        }
    }
}
