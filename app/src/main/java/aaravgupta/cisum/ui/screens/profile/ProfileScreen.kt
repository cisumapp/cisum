package aaravgupta.cisum.ui.screens.profile

import aaravgupta.cisum.R
// import aaravgupta.youtubesdk.shared.ui.GoogleLoginView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.navigation.compose.hiltViewModel

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val uiState = viewModel.uiState.collectAsStateWithLifecycle().value

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(
                text = stringResource(id = R.string.profile_title),
                style = MaterialTheme.typography.headlineMedium
            )
        }

        item {
            Card {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = stringResource(
                            id = if (uiState.isValidatingSession) {
                                R.string.session_state_validating
                            } else {
                                if (uiState.isLoggedIn) {
                                    R.string.session_state_logged_in
                                } else {
                                    R.string.session_state_logged_out
                                }
                            }
                        ),
                        style = MaterialTheme.typography.bodyLarge
                    )

                    if (uiState.isValidatingSession) {
                        CircularProgressIndicator()
                    }

                    if (!uiState.isLoggedIn) {
                        if (uiState.isShowingGoogleSignIn) {
                            Text(
                                text = stringResource(id = R.string.session_google_sign_in_hint),
                                style = MaterialTheme.typography.bodyMedium
                            )

                            GoogleSignInWebView(
                                onLoginSuccess = viewModel::onGoogleLoginSuccess
                            )

                            TextButton(
                                onClick = viewModel::cancelGoogleSignIn,
                                enabled = !uiState.isValidatingSession
                            ) {
                                Text(text = stringResource(id = R.string.session_action_cancel_sign_in))
                            }
                        } else {
                            Button(
                                onClick = viewModel::startGoogleSignIn,
                                enabled = !uiState.isValidatingSession
                            ) {
                                Text(text = stringResource(id = R.string.session_action_google_sign_in))
                            }
                        }
                    } else {
                        TextButton(
                            onClick = viewModel::logoutSession,
                            enabled = !uiState.isValidatingSession
                        ) {
                            Text(text = stringResource(id = R.string.session_action_logout))
                        }
                    }

                    val statusMessage = uiState.statusMessage
                    if (!statusMessage.isNullOrBlank()) {
                        Text(
                            text = statusMessage,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }

        item {
            Text(
                text = stringResource(id = R.string.profile_footer),
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

@Composable
private fun GoogleSignInWebView(
    onLoginSuccess: (String) -> Unit
) {
    AndroidView(
        modifier = Modifier
            .fillMaxWidth()
            .height(440.dp),
        factory = { context ->
            android.view.View(context) // GoogleLoginView(context).apply {
                // this.onLoginSuccess = onLoginSuccess
            // }
        },
        update = { loginView ->
            // loginView.onLoginSuccess = onLoginSuccess
        }
    )
}
