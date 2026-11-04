package aaravgupta.cisum.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable

object Cisum {
    val colors: CisumColors
        @Composable @ReadOnlyComposable get() = LocalCisumColors.current
}

@Composable
fun cisumTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val c = if (darkTheme) DarkCisum else LightCisum
    // Material components read these; cisum's own views read Cisum.colors.
    val scheme = (if (darkTheme) darkColorScheme() else lightColorScheme()).copy(
        primary = c.yellow,
        onPrimary = c.primary,
        background = c.bg,
        onBackground = c.primaryText,
        surface = c.bg,
        onSurface = c.primaryText,
        surfaceVariant = c.surface,
        onSurfaceVariant = c.secondaryText,
        secondary = c.accent,
        outline = c.secondaryText.copy(alpha = 0.3f),
    )
    CompositionLocalProvider(LocalCisumColors provides c) {
        MaterialTheme(colorScheme = scheme, typography = Typography, content = content)
    }
}
